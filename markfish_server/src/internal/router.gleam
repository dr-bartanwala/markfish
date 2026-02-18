import ewe.{type Request, type Response}
import filepath
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/http/response
import gleam/list
import gleam/result
import gleam/string
import internal/stateman.{Add, Get, GetRaw, Remove, Sync}

const delimiter = "||"

const header_file = "config/header.html"

const style_file = "config/style.html"

const footer_file = "config/footer.html"

pub type RouterConfig {
  RouterConfig(user: String, password: String)
}

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

pub fn router(req: Request, state, config: RouterConfig) -> Response {
  case req.path {
    "/" -> handle_file_request(req, state, "kitchen")

    "/message" -> handle_message(req, state, config)

    "/" <> file_name ->
      handle_file_request(req, state, file_name |> clean_file_name)

    _ -> return_invalid_response()
  }
}

fn clean_file_name(req_file_name) {
  req_file_name |> string.replace("%20", " ")
}

fn stream_file(
  file_name: String,
  block_hashes: List(Int),
  subject: Subject(Stream),
  state,
) {
  case block_hashes {
    [hash, ..rest] -> {
      process.call(state, 100, Get(_, file_name, hash))
      |> bit_array.from_string
      |> Chunk
      |> process.send(subject, _)
      stream_file(file_name, rest, subject, state)
    }
    [] -> Nil
  }
}

//the append config file is needed for setting up the configuration
fn append_header_file(subject: Subject(Stream), state) {
  let data = process.call(state, 100, GetRaw(_, header_file))
  Chunk(
    data
    |> bit_array.from_string,
  )
  |> process.send(subject, _)
}

fn append_footer_file(subject: Subject(Stream), state) {
  process.call(state, 30_000, GetRaw(_, footer_file))
  |> bit_array.from_string
  |> Chunk
  |> process.send(subject, _)
  process.send(subject, Done)
}

fn append_styles_file(subject: Subject(Stream), state) {
  process.call(state, 30_000, GetRaw(_, style_file))
  |> bit_array.from_string
  |> Chunk
  |> process.send(subject, _)
}

fn send_file(req: Request, file_name: String, state) -> Response {
  //calling stateman for getting the hashes 
  let hashes = process.call(state, 100, Sync(_, file_name))
  ewe.chunked_body(
    req,
    response.new(200) |> response.set_header("content-type", "text/html"),
    on_init: fn(subject) {
      let _pid =
        fn() {
          append_styles_file(subject, state)
          append_header_file(subject, state)
          stream_file(file_name, hashes, subject, state)
          append_footer_file(subject, state)
        }
        |> process.spawn
    },
    handler: fn(chunked_body, state, message) {
      case message {
        Chunk(data) -> {
          case data {
            <<>> -> ewe.chunked_continue(state)
            _ -> {
              case ewe.send_chunk(chunked_body, data) {
                Ok(Nil) -> ewe.chunked_continue(state)
                Error(_) -> ewe.chunked_stop_abnormal("Failed to send chunk")
              }
            }
          }
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

fn execute_operation(file_name, operation: Operation, state) -> Response {
  case operation {
    Insert(index, hash, block_data) -> {
      process.send(state, Add(file_name, index, hash, block_data))
      return_valid_response()
    }
    Delete(index) -> {
      process.send(state, Remove(file_name, index))
      return_valid_response()
    }
    Fetch -> {
      process.call(state, 100, Sync(_, file_name))
      |> list.fold(<<>>, fn(acc: BitArray, val: Int) -> BitArray {
        acc |> bit_array.append(<<val:64>>)
      })
      |> bit_array.base64_encode(True)
      |> return_sync_response
    }
    Invalid -> {
      return_invalid_response()
    }
  }
}

fn execute_message(file_name: String, base64_data: String, state) -> Response {
  determine_operation(base64_data)
  |> execute_operation(file_name, _, state)
}

fn expand_file_path(file_name) {
  filepath.expand(file_name)
}

fn authenticate_and_proceed(
  user,
  password,
  file_name,
  base64_data,
  state,
  config: RouterConfig,
) -> Response {
  let valid_user = config.user
  let valid_password = config.password
  case { valid_user == user } && { valid_password == password } {
    True ->
      case expand_file_path(file_name) {
        Ok(expanded_file_name) ->
          execute_message(expanded_file_name, base64_data, state)
        Error(_) -> return_invalid_response()
      }
    False -> return_invalid_response()
  }
}

fn handle_message_internal(body: String, state, config) -> Response {
  case body |> string.split(delimiter) {
    [user, password, file_name, base64_data] ->
      authenticate_and_proceed(
        user,
        password,
        file_name,
        base64_data,
        state,
        config,
      )
    _ -> {
      return_invalid_response()
    }
  }
}

fn handle_message(req: Request, state, config) -> Response {
  case req |> ewe.read_body(10_240) {
    Ok(ewe_req) -> {
      ewe_req.body
      |> bit_array.to_string
      |> result.unwrap("")
      |> handle_message_internal(state, config)
    }
    Error(_) -> return_invalid_response()
  }
}

fn handle_file_request(req: Request, state, file_name: String) -> Response {
  case expand_file_path(file_name) {
    Ok(expanded_file_name) -> send_file(req, expanded_file_name, state)
    Error(_) -> return_invalid_response()
  }
}
