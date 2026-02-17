import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor

pub type Message {
  Insert(index: Int, value: Int, block: String)
  Delete(index: Int)
  GetState(reply_with: Subject(List(Int)))
}

fn apply_insert(current_state: List(Int), index: Int, val: Int) -> List(Int) {
  let #(before, after) = current_state |> list.split(index)
  list.flatten([before, [val], after])
}

fn apply_delete(current_state: List(Int), index: Int) -> List(Int) {
  let #(before, after) = current_state |> list.split(index)
  list.append(before, list.drop(after, 1))
}

fn handle_message(state: State, message: Message) {
  case message {
    Insert(index, value, block_data) ->
      State(apply_insert(state.existing_hashes, index, value)) |> actor.continue
    Delete(index) ->
      State(apply_delete(state.existing_hashes, index)) |> actor.continue
    GetState(client) -> {
      process.send(client, state.existing_hashes)
      actor.continue(state)
    }
  }
}

pub type State {
  State(existing_hashes: List(Int))
}

pub fn start_connection(initial_hashes: List(Int)) {
  let state = State(initial_hashes)
  let assert Ok(actor) =
    actor.new(state) |> actor.on_message(handle_message) |> actor.start
  actor.data
}
