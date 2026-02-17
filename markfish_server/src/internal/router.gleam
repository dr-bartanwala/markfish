import ewe.{type Request, type Response}
import filepath
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/result
import gleam/string
import gleam/time/timestamp
import internal/state.{type StateMessage, Add, Get, Remove, Sync}

const delimiter = "||"

type Operation {
  Insert(index: Int, value: Int, blockdata: String)
  Delete(index: Int)
  Fetch
  Invalid
}

type Stream {
  Chunk(BitArray)
  Done
}

fn stream_file(
  folded_file_name: String,
  block_hashes: List(Int),
  subject: Subject(Stream),
  state,
) {
  case block_hashes {
    [hash, ..rest] -> {
      let data =
        process.call(state, 100, Get(_, folded_file_name, hash))
        |> bit_array.from_string

      process.send(subject, Chunk(data))
      stream_file(folded_file_name, rest, subject, state)
    }
    [] -> process.send(subject, Done)
  }
}

fn send_file(req: Request, folded_file_name: String, state) -> Response {
  let hashes = process.call(state, 100, Sync(_, folded_file_name))
  ewe.chunked_body(
    req,
    response.new(200) |> response.set_header("content-type", "text/html"),
    on_init: fn(subject) {
      let _pid =
        fn() { stream_file(folded_file_name, hashes, subject, state) }
        |> process.spawn
    },
    handler: fn(chunked_body, state, message) {
      case message {
        Chunk(data) ->
          case ewe.send_chunk(chunked_body, data) {
            Ok(Nil) -> ewe.chunked_continue(state)
            Error(_) -> ewe.chunked_stop_abnormal("Failed to send chunk")
          }
        Done -> ewe.chunked_stop()
      }
    },
    on_close: fn(_conn, _state) { Nil },
  )
}

fn return_invalid_response() -> Response {
  response.new(404)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(ewe.TextData("Invalid Request"))
}

fn return_valid_response() -> Response {
  response.new(200)
  |> response.set_body(ewe.Empty)
}

fn return_sync_response(data: String) -> Response {
  response.new(200)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(ewe.TextData(data))
}

fn determine_operation(base64_data: String) -> Operation {
  case base64_data |> bit_array.base64_decode {
    Ok(<<first_int:64, rest:bits>>) if first_int == 1 -> {
      case rest {
        <<index:64, rest_of_insert:bits>> -> {
          case rest_of_insert {
            <<hash:64, rest_of_data:bits>> -> {
              rest_of_data
              |> bit_array.to_string
              |> result.unwrap("")
              |> Insert(index, hash, _)
            }
            _ -> Invalid
          }
        }
        _ -> Invalid
      }
    }
    Ok(<<first_int:64, rest:bits>>) if first_int == 0 -> {
      case rest {
        <<index:64>> -> {
          Delete(index)
        }
        _ -> Invalid
      }
    }
    Ok(<<first_int:64>>) if first_int == 2 -> {
      Fetch
    }
    _ -> Invalid
  }
}

fn execute_operation(folded_file_name, operation: Operation, state) -> Response {
  case operation {
    Insert(index, hash, block_data) -> {
      echo "Executing Insert"
      echo timestamp.system_time()
      process.send(state, Add(folded_file_name, index, hash, block_data))
      echo timestamp.system_time()
      return_valid_response()
    }
    Delete(index) -> {
      echo "Executing Delete"
      process.send(state, Remove(folded_file_name, index))
      echo timestamp.system_time()
      return_valid_response()
    }
    Fetch -> {
      echo "Executing Fetch"
      echo timestamp.system_time()
      let data =
        process.call(state, 100, Sync(_, folded_file_name))
        |> list.fold(<<>>, fn(acc: BitArray, val: Int) -> BitArray {
          acc |> bit_array.append(<<val:64>>)
        })
        |> bit_array.base64_encode(True)
      echo timestamp.system_time()
      data |> return_sync_response
    }
    Invalid -> {
      return_invalid_response()
    }
  }
}

fn execute_message(
  folded_file_name: String,
  base64_data: String,
  state,
) -> Response {
  determine_operation(base64_data)
  |> execute_operation(folded_file_name, _, state)
}

fn authenticate_and_proceed(
  user,
  password,
  folded_file_name,
  base64_data,
  state,
) -> Response {
  let valid_user = "default"
  let valid_password = "default"
  case
    { valid_user == user }
    && { valid_password == password }
    && { valid_user != "error" }
    && { valid_password != "error" }
  {
    True -> execute_message(folded_file_name, base64_data, state)
    False -> return_invalid_response()
  }
}

fn handle_message_internal(body: String, state) -> Response {
  case body |> string.split(delimiter) {
    [user, password, file_name, base64_data] -> {
      case file_name |> fold_file_name {
        Ok(folded_file_name) ->
          authenticate_and_proceed(
            user,
            password,
            folded_file_name,
            base64_data,
            state,
          )
        Error(_) -> return_invalid_response()
      }
    }
    _ -> {
      return_invalid_response()
    }
  }
}

fn fold_file_name_internal(list: List(String), acc: String) -> String {
  case list {
    [val] -> {
      acc <> val
    }
    [val, ..rest] -> {
      acc <> val <> "_" |> fold_file_name_internal(rest, _)
    }
    [] -> acc
  }
}

fn fold_file_name(file_name: String) -> Result(String, Nil) {
  case filepath.expand(file_name) {
    Ok(path) -> filepath.split(file_name) |> fold_file_name_internal("") |> Ok

    _ -> Error(Nil)
  }
}

fn handle_message(req: Request, state) -> Response {
  echo "starting handle message"
  echo timestamp.system_time()
  let out = case req |> ewe.read_body(10_240) {
    Ok(ewe_req) -> {
      ewe_req.body
      |> bit_array.to_string
      |> result.unwrap("")
      |> handle_message_internal(state)
    }
    Error(_) -> return_invalid_response()
  }
  echo "handle message ends"
  echo timestamp.system_time()
  out
}

fn handle_file_request(req: Request, state, file_name: String) -> Response {
  case file_name |> fold_file_name {
    Ok(folded_file_name) -> send_file(req, folded_file_name, state)
    _ -> return_invalid_response()
  }
}

pub fn router(req: Request, state) -> Response {
  case req |> request.path_segments {
    [] -> {
      response.new(200)
      |> response.set_header("content-type", "text/html")
      |> response.set_body(ewe.TextData("<h1> hello world !!!</h1>"))
    }
    ["message"] -> handle_message(req, state)

    ["file", file_name] -> handle_file_request(req, state, file_name)
    _ -> return_invalid_response()
  }
}
