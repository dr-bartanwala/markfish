import gleam/deque.{type Deque}
import gleam/result
import gleam/set.{type Set}

const global_lookup_size = 5

pub type Operation {
  DoNothing
  Delete(index: Int)
  Insert(index: Int, value: Int)
}

pub type Context {
  Context(
    index: Int,
    pending: List(Int),
    lookup: Set(Int),
    lookup_elements: Deque(Int),
    debug_info: DebugInfo,
  )
}

pub type DebugInfo {
  DebugInfo(required_sync: Bool, insert_count: Int, delete_count: Int)
}

pub fn sync(
  clean: Bool,
  new_hash: Int,
  context: Context,
  handle_operation: fn(Operation) -> Nil,
) -> Context {
  case clean {
    False -> diff_loop(new_hash, context, handle_operation)
    True -> clear_loop(context, handle_operation)
  }
}

fn apply_debug_operation(context: Context, op: Operation) -> Context {
  case op {
    Delete(_) -> {
      Context(
        ..context,
        debug_info: DebugInfo(
          ..context.debug_info,
          delete_count: context.debug_info.delete_count + 1,
          required_sync: True,
        ),
      )
    }
    Insert(_, _) ->
      Context(
        ..context,
        debug_info: DebugInfo(
          ..context.debug_info,
          insert_count: context.debug_info.insert_count + 1,
          required_sync: True,
        ),
      )

    _ -> context
  }
}

fn clear_loop(
  context: Context,
  handle_operation: fn(Operation) -> Nil,
) -> Context {
  case clear(context) {
    #(new_context, DoNothing) -> new_context
    #(new_context, op) -> {
      handle_operation(op)
      new_context
      |> apply_debug_operation(op)
      |> clear_loop(handle_operation)
    }
  }
}

fn diff_loop(
  new_hash: Int,
  context: Context,
  handle_operation: fn(Operation) -> Nil,
) -> Context {
  case diff(new_hash, context, global_lookup_size) {
    #(new_context, Delete(index)) -> {
      handle_operation(Delete(index))
      diff_loop(
        new_hash,
        new_context |> apply_debug_operation(Delete(index)),
        handle_operation,
      )
    }
    #(new_context, op) -> {
      handle_operation(op)
      new_context |> apply_debug_operation(op)
    }
  }
}

pub fn get_new_context(existing_state: List(Int)) {
  Context(
    0,
    pending: existing_state,
    lookup: set.new(),
    lookup_elements: deque.new(),
    debug_info: DebugInfo(False, 0, 0),
  )
  |> refill_set(global_lookup_size)
}

pub fn clear(new_context: Context) -> #(Context, Operation) {
  let context = new_context |> refill_set(global_lookup_size)
  case context.lookup_elements |> deque.is_empty {
    False -> #(context |> shrink_set |> refill_set(1), Delete(context.index))
    True -> #(context, DoNothing)
  }
}

pub fn diff(
  new_hash: Int,
  new_context: Context,
  lookup_size: Int,
) -> #(Context, Operation) {
  let context = new_context |> refill_set(lookup_size)
  let is_present = context |> lookup_set(new_hash)
  let is_front = context |> check_queue_front(new_hash)
  case is_present, is_front {
    True, True -> #(roll_set(context), DoNothing)
    True, False -> #(shrink_set(context), Delete(context.index))
    False, _ -> #(extend_set(context), Insert(context.index, new_hash))
  }
}

fn refill_set(context: Context, count: Int) -> Context {
  let current_size = context.lookup |> set.size
  case context.pending {
    [new, ..rest] if current_size < count ->
      Context(
        ..context,
        pending: rest,
        lookup: context.lookup |> set.insert(new),
        lookup_elements: context.lookup_elements |> deque.push_back(new),
      )
      |> refill_set(count)
    _ -> context
  }
}

fn check_queue_front(context: Context, element: Int) -> Bool {
  context.lookup_elements
  |> deque.pop_front
  |> result.map(fn(pair: #(Int, Deque(Int))) { pair.0 == element })
  |> result.unwrap(False)
}

fn lookup_set(context: Context, element: Int) -> Bool {
  context.lookup |> set.contains(element)
}

fn roll_set(context: Context) -> Context {
  context |> shrink_set |> extend_set
}

fn extend_set(context: Context) -> Context {
  case context.pending {
    [curr, ..rest] ->
      Context(
        ..context,
        index: context.index + 1,
        lookup: context.lookup |> set.insert(curr),
        pending: rest,
        lookup_elements: context.lookup_elements |> deque.push_back(curr),
      )
    _ -> Context(..context, index: context.index + 1)
  }
}

fn shrink_set(context: Context) -> Context {
  context.lookup_elements
  |> deque.pop_front
  |> result.map(fn(pair: #(Int, Deque(Int))) -> Context {
    Context(
      ..context,
      lookup: context.lookup |> set.delete(pair.0),
      lookup_elements: pair.1,
    )
  })
  |> result.unwrap(context)
}
