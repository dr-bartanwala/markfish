//a scanner will scan for changes and maintain connection for each file
//start the scanner with a base dir, and it will maintain child scanners + connections for all child files
import gleam
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import internal/connection.{
  type ConnectionConfig, type Message, ConnectionConfig, start_connection,
}
import internal/diff.{type DebugInfo}
import internal/sync_file.{syncfile}
import simplifile

//child scanner implements an exponential decay 
//50ms -> 200ms -> 2s -> 10s
//on sync message it force

type ChildScannerMessage {
  Initialize(self: Subject(ChildScannerMessage))
  Tick
  Sync
  StopSync
}

type ChildScannerInfo {
  ChildScannerInfo(
    common_info: CommonInfo,
    tick_time_ms: Int,
    counter: Int,
    file: String,
    connection: Subject(Message),
    self: Subject(ChildScannerMessage),
  )
}

fn handle_tick_time_increment(counter: Int) {
  case counter {
    _ if counter < 100 -> 50
    // if the modification time is < 50ms * 100 i.e 5s 
    _ if counter < 200 -> 200
    // if the modification time is < 5 + 200ms * 100 => 25s
    _ if counter < 300 -> 1000
    // if the modification time is < 25 + 1000 * 100 => 125s
    _ -> 10_000
    // Final counter
  }
}

fn handle_child_scanner_message(
  state: ChildScannerInfo,
  message: ChildScannerMessage,
) {
  case message {
    Initialize(self) -> {
      let new_state = ChildScannerInfo(..state, self: self)
      actor.send(new_state.self, Tick)
      actor.continue(new_state)
    }
    Tick -> {
      case syncfile(state.file, state.connection) {
        True -> {
          process.send(state.self, Tick)
          echo "TICK RESET"
          actor.continue(ChildScannerInfo(..state, counter: 0))
        }

        False -> {
          let new_tick_time_ms = handle_tick_time_increment(state.counter)
          process.send_after(state.self, new_tick_time_ms, Tick)
          actor.continue(
            ChildScannerInfo(
              ..state,
              counter: state.counter + 1,
              tick_time_ms: new_tick_time_ms,
            ),
          )
        }
      }
    }
    Sync -> {
      syncfile(state.file, state.connection)
      process.send(state.self, Tick)
      actor.continue(ChildScannerInfo(..state, counter: 0))
    }
    StopSync -> {
      actor.continue(state)
    }
  }
}

fn get_child_scanner(common_info: CommonInfo, file: String) {
  let connection =
    start_connection(ConnectionConfig(
      file,
      common_info.server_addr,
      common_info.user,
      common_info.password,
    ))

  let assert Ok(child) =
    ChildScannerInfo(
      common_info,
      50,
      0,
      file,
      connection,
      process.new_subject(),
    )
    |> actor.new
    |> actor.on_message(handle_child_scanner_message)
    |> actor.start

  process.send(child.data, Initialize(child.data))
  child.data
}

fn create_child_scanner(state: ScannerInfo, file: String) -> ScannerInfo {
  let child = get_child_scanner(state.common_info, file)
  ScannerInfo(
    ..state,
    child_scanners: state.child_scanners |> dict.insert(file, child),
  )
}

fn handle_scan_internal(list, state) -> ScannerInfo {
  case list {
    [file, ..rest] ->
      state |> create_child_scanner(file) |> handle_scan_internal(rest, _)
    [] -> state
  }
}

fn handle_scan(state: ScannerInfo) -> ScannerInfo {
  let files = simplifile.get_files(state.common_info.base_dir)
  echo files
  simplifile.get_files(state.common_info.base_dir)
  |> result.unwrap([])
  |> handle_scan_internal(state)
}

//expects the relative name of the file from the base dir
pub type ScannerMessage {
  Scan
}

pub type CommonInfo {
  CommonInfo(
    base_dir: String,
    user: String,
    password: String,
    server_addr: String,
  )
}

type ScannerInfo {
  ScannerInfo(
    common_info: CommonInfo,
    child_scanners: Dict(String, Subject(ChildScannerMessage)),
  )
}

fn handle_scanner_message(state: ScannerInfo, message: ScannerMessage) {
  case message {
    Scan -> handle_scan(state) |> actor.continue
  }
}

pub fn get_scanner(common_info: CommonInfo) {
  let assert Ok(actor) =
    ScannerInfo(common_info, dict.new())
    |> actor.new
    |> actor.on_message(handle_scanner_message)
    |> actor.start
  actor.data
}
