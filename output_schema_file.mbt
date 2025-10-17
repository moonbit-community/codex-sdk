///|
priv struct OutputSchemaFile {
  schema_path : String
  cleanup : async () -> Unit
}

///|
extern "C" fn random() -> UInt = "arc4random"

///|
async fn create_output_schema_file(schema : Json) -> OutputSchemaFile {
  let dir = "/tmp/codex-output-schema-\{random()}"
  let path = "\{dir}/schema.json"
  @fs.mkdir(dir, permission=0o700)
  let cleanup = async fn() { @fs.rmdir(dir, recursive=true) }
  try {
    let file = @fs.create(path, permission=0o600)
    file.write(schema.stringify(indent=2))
    file.close()
    return { schema_path: path, cleanup }
  } catch {
    e => {
      cleanup()
      raise e
    }
  }
}
