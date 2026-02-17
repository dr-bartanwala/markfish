import envoy
import filepath
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import simplifile

import internal/fileman.{
  type FilemanMessage, DeleteFile, ReadFile, WriteFile, start_fileman,
}

fn get_filename(file: String, blockhash: Int) -> String {
  let file_name =
    "/data/" <> file <> "/blocks/" <> blockhash |> int.to_string <> ".html"
  let _ = simplifile.create_directory_all(file_name |> filepath.directory_name)
  let _ = simplifile.create_file(file_name)
  file_name
}

fn get_blockdata_filename(file: String) -> String {
  let file_name = {
    "/data/" <> file <> "/blockdata.markfish"
  }
  let _ = simplifile.create_directory_all(file_name |> filepath.directory_name)
  let _ = simplifile.create_file(file_name)
  file_name
}

fn apply_insert(current_state: List(Int), index: Int, val: Int) -> List(Int) {
  let #(before, after) = current_state |> list.split(index)
  list.flatten([before, [val], after])
}

fn apply_delete(current_state: List(Int), index: Int) -> #(Int, List(Int)) {
  let #(before, after) = current_state |> list.split(index)
  let value = after |> list.first |> result.unwrap(0)
  #(value, list.append(before, list.drop(after, 1)))
}

fn write_new_list(state: State, file: String, new_list: List(Int)) {
  let data =
    new_list
    |> list.fold("", fn(acc: String, val: Int) {
      acc <> int.to_string(val) <> " "
    })
  process.send(state.fileman, WriteFile(get_blockdata_filename(file), data))
}

fn handle_get(state: State, file: String, blockhash: Int) -> String {
  process.call(state.fileman, 1000, ReadFile(_, get_filename(file, blockhash)))
}

fn handle_add(
  state: State,
  file: String,
  index: Int,
  blockhash: Int,
  blockdata: String,
) {
  process.send(
    state.fileman,
    WriteFile(get_filename(file, blockhash), blockdata),
  )
  let new_list = handle_sync(state, file) |> apply_insert(index, blockhash)
  let _ = write_new_list(state, file, new_list)
}

fn handle_remove(state: State, file: String, index: Int) {
  let #(blockhash, new_list) = handle_sync(state, file) |> apply_delete(index)
  case new_list |> list.contains(blockhash) {
    False -> {
      let _ = simplifile.delete(get_filename(file, blockhash))
      Nil
    }
    True -> Nil
  }
  let _ = write_new_list(state, file, new_list)
}

fn handle_sync(state: State, file: String) -> List(Int) {
  let out =
    process.call(state.fileman, 100, ReadFile(_, get_blockdata_filename(file)))
    |> string.replace("\r\n", "")
    |> string.replace("\n", "")
    |> string.split(" ")
  out
  |> list.fold([], fn(acc: List(Int), val: String) -> List(Int) {
    case val |> int.parse {
      Ok(int) -> [int, ..acc]
      _ -> acc |> list.reverse
    }
  })
}

fn handle_message(state: State, msg: StateMessage) {
  case msg {
    Add(file, index, blockhash, blockdata) -> {
      let _ = handle_add(state, file, index, blockhash, blockdata)
      actor.continue(state)
    }

    Remove(file, index) -> {
      let _ = handle_remove(state, file, index)
      actor.continue(state)
    }

    Sync(client, file) -> {
      handle_sync(state, file) |> process.send(client, _)
      actor.continue(state)
    }

    Get(client, file, blockhash) -> {
      handle_get(state, file, blockhash) |> process.send(client, _)
      actor.continue(state)
    }
  }
}

//the current filename is folded filename : "dir_dir_dir_filename" 
pub type StateMessage {
  Add(file: String, index: Int, blockhash: Int, blockdata: String)
  Get(reply_with: Subject(String), file: String, blockhash: Int)
  Remove(file: String, index: Int)
  Sync(reply_with: Subject(List(Int)), file: String)
}

pub type State {
  State(fileman: Subject(FilemanMessage))
}

pub fn start_state() {
  let fileman = start_fileman()
  let state = State(fileman)
  let assert Ok(actor) =
    actor.new(state) |> actor.on_message(handle_message) |> actor.start
  actor.data
}
