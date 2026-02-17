import filepath
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import simplifile

//receives validated & expanded filenames from the router
pub type FilemanMessage {
  ReadFile(reply_with: Subject(String), file_name: String)
  WriteFile(file_name: String, data: String)
  DeleteFile(file_name: String)
}

type Read {
  Read(reply_with: Subject(String), file: String)
}

type Write {
  Write(file: String, data: String)
  Delete(file: String)
}

fn handle_read(state, message: Read) {
  let out = case message.file |> simplifile.read {
    Ok(val) -> {
      val
    }
    Error(_) -> ""
  }
  process.send(message.reply_with, out)
  actor.continue(state)
}

fn handle_write(state, message: Write) {
  let _ = case message {
    Write(file, data) -> file |> simplifile.write(data)
    Delete(file) -> simplifile.delete(file)
  }
  actor.continue(state)
}

fn get_filereader(directory: String) {
  let assert Ok(actor) =
    actor.new(directory)
    |> actor.on_message(handle_read)
    |> actor.start
  actor.data
}

fn get_filewriter(directory: String) {
  let assert Ok(actor) =
    actor.new(directory) |> actor.on_message(handle_write) |> actor.start
  actor.data
}

fn create_file_directory(complete_file_name: String) -> Nil {
  let _ =
    simplifile.create_directory_all(
      complete_file_name |> filepath.directory_name,
    )
  let _ = simplifile.create_file(complete_file_name)
  Nil
}

fn handle_read_file(state: State, client, file) {
  let complete_file_name = filepath.join(state.directory, file)
  process.call(state.file_reader, 100, Read(_, complete_file_name))
  |> process.send(client, _)
  actor.continue(state)
}

fn handle_write_file(state: State, file, data) {
  let complete_file_name = filepath.join(state.directory, file)
  create_file_directory(complete_file_name)
  process.send(state.file_writer, Write(complete_file_name, data))
  actor.continue(state)
}

fn handle_delete_file(state: State, file) {
  let complete_file_name = filepath.join(state.directory, file)
  process.send(state.file_writer, Delete(complete_file_name))
  actor.continue(state)
}

fn handle_message(state: State, message: FilemanMessage) {
  case message {
    ReadFile(client, file_name) -> handle_read_file(state, client, file_name)
    WriteFile(file_name, data) -> handle_write_file(state, file_name, data)
    DeleteFile(file_name) -> handle_delete_file(state, file_name)
  }
}

type State {
  State(
    file_reader: Subject(Read),
    file_writer: Subject(Write),
    directory: String,
  )
}

pub fn start_fileman(directory) {
  let file_reader = get_filereader(directory)
  let file_writer = get_filewriter(directory)
  let assert Ok(actor) =
    actor.new(State(file_reader, file_writer, directory))
    |> actor.on_message(handle_message)
    |> actor.start
  actor.data
}
