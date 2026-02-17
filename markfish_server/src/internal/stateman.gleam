import envoy
import filepath
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import internal/fileman.{
  type FilemanMessage, DeleteFile, ReadFile, WriteFile, start_fileman,
}
import simplifile

//the filename received is the folded filename : "dir_dir_dir_filename" 
pub type StatemanMessage {
  Add(file: String, index: Int, blockhash: Int, blockdata: String)
  Get(reply_with: Subject(String), file: String, blockhash: Int)
  Remove(file: String, index: Int)
  Sync(reply_with: Subject(List(Int)), file: String)
}

type InternalState {
  InternalState(fileman: Subject(FilemanMessage))
}

pub fn start_stateman() {
  let fileman = start_fileman()
  let state = InternalState(fileman)
  let assert Ok(actor) =
    actor.new(state) |> actor.on_message(handle_message) |> actor.start
  actor.data
}

//determines the storage structure for all files
//appends file with extentions
fn get_filename(file: String, blockhash: Int) -> String {
  let file_name =
    "/data/" <> file <> "/blocks/" <> blockhash |> int.to_string <> ".html"
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

fn write_blockdata(state: InternalState, file: String, new_list: List(Int)) {
  let data =
    new_list
    |> list.fold("", fn(acc: String, val: Int) {
      acc <> int.to_string(val) <> " "
    })
  process.send(state.fileman, WriteFile(get_blockdata_filename(file), data))
}

fn read_blockdata(state: InternalState, file: String) -> List(Int) {
  process.call(state.fileman, 100, ReadFile(_, get_blockdata_filename(file)))
  |> string.replace("\r\n", "")
  |> string.replace("\n", "")
  |> string.split(" ")
  |> list.fold([], fn(acc: List(Int), val: String) -> List(Int) {
    case val |> int.parse {
      Ok(int) -> [int, ..acc]
      _ -> acc |> list.reverse
    }
  })
}

fn handle_get(state: InternalState, file: String, blockhash: Int) -> String {
  process.call(state.fileman, 1000, ReadFile(_, get_filename(file, blockhash)))
}

fn handle_add(
  state: InternalState,
  file: String,
  index: Int,
  blockhash: Int,
  blockdata: String,
) {
  process.send(
    state.fileman,
    WriteFile(get_filename(file, blockhash), blockdata),
  )
  handle_sync(state, file)
  |> apply_insert(index, blockhash)
  |> write_blockdata(state, file, _)
}

fn handle_remove(state: InternalState, file: String, index: Int) {
  let #(blockhash, new_list) = handle_sync(state, file) |> apply_delete(index)
  case new_list |> list.contains(blockhash) {
    False -> {
      process.send(state.fileman, DeleteFile(get_filename(file, blockhash)))
    }
    True -> Nil
  }
  write_blockdata(state, file, new_list)
}

fn handle_sync(state: InternalState, file: String) -> List(Int) {
  read_blockdata(state, file)
}

fn handle_message(state: InternalState, msg: StatemanMessage) {
  case msg {
    Add(file, index, blockhash, blockdata) -> {
      handle_add(state, file, index, blockhash, blockdata)
      actor.continue(state)
    }

    Remove(file, index) -> {
      handle_remove(state, file, index)
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
