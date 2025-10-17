///|
async test {
  // async iterator
  let iterator = AsyncGenerator::new(fn(yield_) {
    for i = 0; ; i = i + 1 {
      yield_(i) catch {
        Failure(e) => {
          guard e == "error"
        }
        e => raise e
      }
    }
  })
  inspect(iterator.next(), content="Some(0)")
  inspect(iterator.throws(Failure("error")), content="Some(1)")
  inspect(iterator.returns(), content="None")
  inspect(iterator.next(), content="None")
}
