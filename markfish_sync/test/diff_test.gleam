import gleam/erlang/process.{type Subject}
import gleam/list
import gleeunit
import internal/diff.{type Context, type Operation, sync}
import internal/test_server.{type Message, GetDebug, GetState, start_connection}

pub fn main() -> Nil {
  gleeunit.main()
}

fn sync_loop(values: List(Int), context: Context, handle_operation) {
  case values {
    [value, ..rest] ->
      sync(False, value, context, handle_operation)
      |> sync_loop(rest, _, handle_operation)

    [] -> {
      sync(True, 0, context, handle_operation)
    }
  }
}

fn create_handle_operation(
  server_addr: Subject(Message),
) -> fn(Operation) -> Nil {
  fn(op: Operation) {
    case op {
      diff.Insert(index, value) ->
        process.send(server_addr, test_server.Insert(index, value, ""))

      diff.Delete(index) -> process.send(server_addr, test_server.Delete(index))

      _ -> Nil
    }
  }
}

fn execute_sync(values: List(Int), server_addr: Subject(Message)) {
  let existing_state = process.call(server_addr, 10, GetState)
  sync_loop(
    values,
    diff.get_new_context(existing_state.0),
    create_handle_operation(server_addr),
  )
}

fn execute_test(hashes, new_hashes) {
  let subject = start_connection(hashes, [])
  execute_sync(new_hashes, subject)
  let modified_state = process.call(subject, 10, GetState)
  assert new_hashes == modified_state.0
}

pub fn diff_test() {
  let hashes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  let new_hashes = [1, 2, 3, 5, 7, 8, 15, 11]
  execute_test(hashes, new_hashes)
}

pub fn clear_loop_test() {
  let hashes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  let new_hashes = []
  execute_test(hashes, new_hashes)
}

pub fn identity_test() {
  let hashes = [1, 2, 3]
  execute_test(hashes, hashes)
}

pub fn start_from_empty_test() {
  let hashes = []
  let new_hashes = [1, 2, 3]
  execute_test(hashes, new_hashes)
}

pub fn large_scale_insertion_test() {
  let hashes = list.range(1, 20)
  let new_hashes =
    list.flatten([[0], list.range(1, 10), [99], list.range(11, 20), [100]])
  execute_test(hashes, new_hashes)
}

pub fn duplicate_values_test() {
  let hashes = [1, 1, 1, 2]
  let new_hashes = [1, 2, 1, 1]
  execute_test(hashes, new_hashes)
}

pub fn total_replacement_test() {
  let hashes = [1, 2, 3]
  let new_hashes = [7, 8, 9, 10]
  execute_test(hashes, new_hashes)
}

pub fn heavy_duplicate_churn_test() {
  let hashes = [1, 1, 2, 2, 1, 1]
  let new_hashes = [2, 1, 1, 2]
  // Mix of deletion and reordering of identical values
  execute_test(hashes, new_hashes)
}

pub fn middle_gutting_test() {
  let hashes = [1, 2, 3, 4, 5, 6, 7]
  let new_hashes = [1, 7]
  // Delete everything in between
  execute_test(hashes, new_hashes)
}

pub fn swap_endpoints_test() {
  // Tests if the diff correctly handles the first and last elements swapping
  let hashes = [1, 2, 3, 4, 5]
  let new_hashes = [5, 2, 3, 4, 1]
  execute_test(hashes, new_hashes)
}

pub fn rotation_test() {
  // Shift all elements one to the right
  let hashes = [1, 2, 3, 4, 7, 10, 11, 1234]
  let new_hashes = [4, 1, 2, 3]
  execute_test(hashes, new_hashes)
}

pub fn single_to_empty_test() {
  execute_test([1], [])
}
