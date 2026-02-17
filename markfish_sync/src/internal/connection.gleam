import filepath
import gleam/erlang/process.{type Subject}
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp

import gleam/bit_array

const state_expiration_time = 500.0

const data_delimiter = "||"

pub type ConnectionConfig {
  ConnectionConfig(
    file: String,
    server_address: String,
    user: String,
    password: String,
  )
}

type ServerRequest {
  InsertReq(data: BitArray)
  DeleteReq(data: BitArray)
  SyncReq
}

pub type Message {
  SyncState(reply_with: Subject(Bool))
  Insert(index: Int, value: Int, block: String)
  Delete(index: Int)
  GetState(reply_with: Subject(List(Int)))
}

fn call_server_internal(address: String, body: String) -> String {
  echo "calling server"
  echo timestamp.system_time()
  let assert Ok(base_req) = request.to(address)

  let req =
    base_req
    |> request.set_method(http.Post)
    |> request.set_scheme(http.Http)
    |> request.prepend_header("accept", "text/plain; charset=UTF-8")
    |> request.set_body(body)

  echo "req"
  echo req

  let out = case hackney.send(req) {
    Ok(resp) -> {
      case resp.status == 200 {
        True -> resp.body
        False -> {
          echo "call failed"
          echo resp.body
          ""
        }
      }
    }
    _ -> {
      echo "threw error"
      ""
    }
  }

  echo "calling server complete"
  echo timestamp.system_time()
  out
}

fn not_call_server_internal(address: String, body: String) -> String {
  echo "calling server"
  echo timestamp.system_time()
  let req = request.to(address)
  echo req
  let base_req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("127.0.0.1")
    |> request.set_port(8000)
    |> request.set_path("/message")
    |> request.set_scheme(http.Http)

  let req =
    request.prepend_header(base_req, "accept", "text/plain; charset=UTF-8")
    |> request.prepend_header("connection", "keep-alive")
    |> request.set_body(body)

  let out = case httpc.send(req) {
    Ok(resp) -> {
      case resp.status == 200 {
        True -> resp.body
        False -> {
          echo "call failed"
          ""
        }
      }
    }
    _ -> {
      echo "threw error"
      ""
    }
  }
  echo "calling server complete"
  echo timestamp.system_time()
  out
}

fn get_list_from_bitarray(array: BitArray, acc: List(Int)) {
  case array {
    <<val:64, rest:bits>> -> get_list_from_bitarray(rest, [val, ..acc])
    _ -> list.reverse(acc)
  }
}

fn modify_state_from_output(output: String, state: State) -> State {
  let hashes =
    get_list_from_bitarray(
      output |> bit_array.base64_decode |> result.unwrap(<<>>),
      [],
    )
  State(..state, existing_hashes: hashes)
}

fn fill_header(config: ConnectionConfig, data: String) -> String {
  config.user
  <> data_delimiter
  <> config.password
  <> data_delimiter
  <> config.file |> filepath.base_name |> filepath.strip_extension
  <> data_delimiter
  <> data
}

fn call_server(request: ServerRequest, state: State) -> State {
  case request {
    InsertReq(data) ->
      <<1:64>> |> bit_array.append(data) |> bit_array.base64_encode(False)

    DeleteReq(data) ->
      <<0:64>> |> bit_array.append(data) |> bit_array.base64_encode(False)

    SyncReq -> <<2:64>> |> bit_array.base64_encode(False)
  }
  |> fn(data: String) -> State {
    let output =
      fill_header(state.config, data)
      |> call_server_internal(state.config.server_address <> "/message", _)

    case output {
      "" if request == SyncReq -> {
        echo "this was a sync request still empty"
        state
      }
      "" -> {
        state
      }
      _ -> state |> modify_state_from_output(output, _)
    }
  }
}

fn encode_to_base64(msg: Message) -> ServerRequest {
  case msg {
    Insert(index, value, block_data) -> {
      <<index:64>>
      |> bit_array.append(<<value:64>>)
      |> bit_array.append(block_data |> bit_array.from_string)
      |> InsertReq
    }
    Delete(index) -> {
      <<index:64>>
      |> DeleteReq
    }

    SyncState(_) -> SyncReq
    GetState(_) -> SyncReq
  }
}

fn sync_state_if_required(state: State) -> State {
  echo "syncstate check starts"
  echo timestamp.system_time()
  let state_timestamp: Float = state.latest_fetch_timestamp
  let current_timestamp: Float =
    timestamp.system_time() |> timestamp.to_unix_seconds

  let out = case current_timestamp -. state_timestamp >. state_expiration_time {
    True -> state |> handle_sync_internal
    False -> state
  }
  echo "syncstate completes"
  echo timestamp.system_time()
  out
}

//all of these operations are specific to files
//locally, the state will be stored as, .filename.markfish.state
//it will try to get the state from this
//if the file doesn't exist, it will return false
fn apply_insert(current_state: List(Int), index: Int, val: Int) -> List(Int) {
  let #(before, after) = current_state |> list.split(index)
  list.flatten([before, [val], after])
}

fn apply_delete(current_state: List(Int), index: Int) -> List(Int) {
  let #(before, after) = current_state |> list.split(index)
  list.append(before, list.drop(after, 1))
}

fn handle_insert(index, value, block_data, state) -> State {
  encode_to_base64(Insert(index, value, block_data)) |> call_server(state)
  State(
    ..state,
    existing_hashes: apply_insert(state.existing_hashes, index, value),
  )
}

fn handle_delete(index, state) -> State {
  encode_to_base64(Delete(index)) |> call_server(state)
  State(..state, existing_hashes: apply_delete(state.existing_hashes, index))
}

fn handle_get(client, state: State) -> State {
  let new_state = sync_state_if_required(state)
  process.send(client, new_state.existing_hashes)
  new_state
}

//calls the server for sync
fn handle_sync_internal(state: State) -> State {
  echo "calling server"
  echo timestamp.system_time()
  echo call_server(SyncReq, state)
  echo "calling server complete"
  echo timestamp.system_time()
  State(
    ..call_server(SyncReq, state),
    latest_fetch_timestamp: timestamp.system_time()
      |> timestamp.to_unix_seconds,
  )
}

fn handle_sync(client, state: State) -> State {
  let new_state = handle_sync_internal(state)
  process.send(client, True)
  new_state
}

fn handle_message(state: State, message: Message) {
  echo "handle message starts"
  echo timestamp.system_time()
  let out =
    sync_state_if_required(state)
    |> handle_message_internal(message, _)
  echo "handle message completes"
  echo timestamp.system_time()
  out
}

fn handle_message_internal(message: Message, state: State) {
  case message {
    Insert(index, value, block_data) ->
      handle_insert(index, value, block_data, state)
      |> actor.continue
    Delete(index) ->
      handle_delete(index, state)
      |> actor.continue
    SyncState(client) ->
      handle_sync(client, state)
      |> actor.continue
    GetState(client) ->
      handle_get(client, state)
      |> actor.continue
  }
}

pub type State {
  State(
    existing_hashes: List(Int),
    config: ConnectionConfig,
    latest_fetch_timestamp: Float,
  )
}

pub fn start_connection(config: ConnectionConfig) {
  echo "calling fetch state"
  let state =
    State([], config, timestamp.system_time() |> timestamp.to_unix_seconds())
    |> handle_sync_internal
  let assert Ok(actor) =
    actor.new(state) |> actor.on_message(handle_message) |> actor.start

  echo "synced"
  echo state.existing_hashes
  actor.data
}
