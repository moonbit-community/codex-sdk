///|
/// Read work items from JSON file or stdin.
async fn read_items(file : String?) -> Array[WorkItem] raise Error {
  let content = match file {
    Some(path) => @fs.read_file(path).text() catch { e => raise e }
    None => @stdio.stdin.read_all().text()
  }
  let json = @json.parse(content) catch { e => raise e }
  guard json is Array(items) else {
    raise @builtin.Failure("Expected JSON array of work items")
  }
  let work_items : Array[WorkItem] = []
  for i, item in items {
    let input : WorkItemInput = @json.from_json(item) catch { e => raise e }
    work_items.push({
      index: i,
      label: input.label,
      review: input.review,
      fix: input.fix,
    })
  }
  work_items
}
