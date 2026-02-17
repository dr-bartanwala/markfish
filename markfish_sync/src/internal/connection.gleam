import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp

import gleam/bit_array

const state_expiration_time = 5.0

const data_delimiter = "\r\n"

//the connection process will crash without throwing any error in case the connection to the server doesn't work
//this will be handled by the parent process which will act like a superviser
//
// parent -> gets a request with sync(file_name) : invokes a process specifically for that task, and keeps it running
// and if the process crashes then it gives a response

pub type ConnectionConfig {
  ConnectionConfig(
    file: String,
    server_address: String,
    user: String,
    password: String,
  )
}

type ServerRequest {
  InsertReq(data: String)
  DeleteReq(data: String)
  SyncReq
}

pub type Message {
  SyncState(reply_with: Subject(Bool))
  Insert(index: Int, value: Int, block: String)
  Delete(index: Int)
  GetState(reply_with: Subject(List(Int)))
}

//this function can fail
fn call_server_internal(address: String, body: String) -> String {
  let assert Ok(base_req) = request.to(address)
  let req =
    request.prepend_header(base_req, "accept", "text/plain; charset=UTF-8")
    |> request.set_body(body)
  let assert Ok(resp) = httpc.send(req)
  assert resp.status == 200
  resp.body
}

fn get_list_from_bitarray(array: BitArray, acc: List(Int)) {
  case array {
    <<val:64, rest:bits>> -> get_list_from_bitarray(rest, [val, ..acc])
    _ -> list.reverse(acc)
  }
}

fn modify_state_from_output(output: String, state: State) -> State {
  //the sync request will output a list of integers, size 6
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
  <> config.file
  <> data_delimiter
  <> data
}

fn call_server(request: ServerRequest, state: State) -> State {
  case request {
    InsertReq(data) -> <<1:64>> |> bit_array.base64_encode(False) <> data

    DeleteReq(data) -> <<0:64>> |> bit_array.base64_encode(False) <> data

    SyncReq -> ""
  }
  |> fn(data: String) -> State {
    let output =
      fill_header(state.config, data)
      |> call_server_internal(state.config.server_address <> "/message")
    case output {
      "" -> state
      _ -> state |> modify_state_from_output(output, _)
    }
  }
}

// we are using an FNV 64bit hash, so the int value will be set to 64bit
fn encode_to_base64(msg: Message) -> ServerRequest {
  case msg {
    Insert(index, value, block_data) ->
      <<index:64>>
      |> bit_array.append(<<value:64>>)
      |> bit_array.append(block_data |> bit_array.from_string)
      |> bit_array.base64_encode(True)
      |> InsertReq

    Delete(index) ->
      <<index:64>>
      |> bit_array.base64_encode(True)
      |> DeleteReq

    SyncState(_) -> SyncReq
    GetState(_) -> SyncReq
  }
}

fn sync_state_if_required(state: State) -> State {
  let state_timestamp: Float = state.latest_fetch_timestamp
  let current_timestamp: Float =
    timestamp.system_time() |> timestamp.to_unix_seconds
  case current_timestamp -. state_timestamp >. state_expiration_time {
    True -> state |> handle_sync_internal
    False -> state
  }
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
  process.send(client, state.existing_hashes)
  state
}

//calls the server for sync
fn handle_sync_internal(state: State) -> State {
  call_server(SyncReq, state)
}

fn handle_sync(client, state: State) -> State {
  let new_state = handle_sync_internal(state)
  process.send(client, True)
  new_state
}

fn handle_message(state: State, message: Message) {
  sync_state_if_required(state)
  |> handle_message_internal(message, _)
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
  let state =
    State([], config, timestamp.system_time() |> timestamp.to_unix_seconds())

  let assert Ok(actor) =
    actor.new(state) |> actor.on_message(handle_message) |> actor.start
  process.call(actor.data, 3000, SyncState)
  actor.data
}
