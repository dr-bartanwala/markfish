import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor

pub type DebugInfo {
  DebugInfo(total_operations: Int, inserts: Int, deletes: Int)
}

pub type Message {
  Insert(index: Int, value: Int, block: String)
  Delete(index: Int)
  GetState(reply_with: Subject(#(List(Int), List(String))))
  GetDebug(reply_with: Subject(DebugInfo))
}

fn apply_debug_info(current_debug_info: DebugInfo, message: Message) {
  case message {
    Insert(_, _, _) ->
      DebugInfo(..current_debug_info, inserts: current_debug_info.inserts + 1)
    Delete(_) ->
      DebugInfo(..current_debug_info, deletes: current_debug_info.deletes + 1)
    _ -> current_debug_info
  }
}

fn apply_list_insert(current_state: List(v), index: Int, val: v) -> List(v) {
  let #(before, after) = current_state |> list.split(index)
  list.flatten([before, [val], after])
}

fn apply_list_delete(current_state: List(v), index: Int) -> List(v) {
  let #(before, after) = current_state |> list.split(index)
  list.append(before, list.drop(after, 1))
}

fn apply_state_insert(
  current_state: State,
  index: Int,
  hash: Int,
  block: String,
) -> State {
  State(
    ..current_state,
    hashes: current_state.hashes |> apply_list_insert(index, hash),
    blocks: current_state.blocks |> apply_list_insert(index, block),
  )
}

fn apply_state_delete(current_state: State, index: Int) -> State {
  State(
    ..current_state,
    hashes: current_state.hashes |> apply_list_delete(index),
    blocks: current_state.blocks |> apply_list_delete(index),
  )
}

fn handle_message(state: State, message: Message) {
  let new_debug_info = state.debug_info |> apply_debug_info(message)
  case message {
    Insert(index, value, block_data) ->
      State(
        ..state
        |> apply_state_insert(index, value, block_data),
        debug_info: new_debug_info,
      )
      |> actor.continue
    Delete(index) ->
      State(
        ..state
        |> apply_state_delete(index),
        debug_info: new_debug_info,
      )
      |> actor.continue
    GetState(client) -> {
      process.send(client, #(state.hashes, state.blocks))
      actor.continue(state)
    }
    GetDebug(client) -> {
      process.send(client, state.debug_info)
      actor.continue(state)
    }
  }
}

pub type State {
  State(hashes: List(Int), blocks: List(String), debug_info: DebugInfo)
}

pub fn start_connection(initial_hashes: List(Int), initial_blocks: List(String)) {
  let state = State(initial_hashes, initial_blocks, DebugInfo(0, 0, 0))
  let assert Ok(actor) =
    actor.new(state) |> actor.on_message(handle_message) |> actor.start
  actor.data
}
