///|
/// PostgreSQL process boundary shared by native MoonBit adapters.
///
/// The database client remains `psql`, but all SQL callers are compiled
/// MoonBit code. Connection credentials stay in the inherited environment;
/// they are never accepted as command-line payloads or logged.
pub(all) suberror PostgresError {
  Process(String)
  Failed(String)
} derive(Debug)

///|
pub(all) struct Connection {
  psql : String
  host : String
  port : String
  user : String
  database : String
}

///|
fn env_or(key : String, fallback : String) -> String {
  @env.get_env_var(key).unwrap_or(fallback)
}

///|
pub fn connection_from_env() -> Connection {
  {
    psql: env_or("PSQL_BIN", "psql"),
    host: env_or("PGHOST", "/tmp"),
    port: env_or("PGPORT", "5432"),
    user: env_or("PGUSER", "moonproj"),
    database: env_or("PGDATABASE", "moonproj"),
  }
}

///|
pub fn Connection::with_overrides(
  self : Connection,
  psql~ : String?,
  host~ : String?,
  port~ : String?,
  user~ : String?,
  database~ : String?,
) -> Connection {
  {
    psql: psql.unwrap_or(self.psql),
    host: host.unwrap_or(self.host),
    port: port.unwrap_or(self.port),
    user: user.unwrap_or(self.user),
    database: database.unwrap_or(self.database),
  }
}

///|
fn process_text(process : @spawn.CompletedProcess, key : String) -> String {
  match process.to_json() {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn process_status(process : @spawn.CompletedProcess) -> Int {
  match process.to_json() {
    Object(fields) =>
      match fields.get("status") {
        Some(Number(value, ..)) => value.to_int()
        _ => -1
      }
    _ => -1
  }
}

///|
fn command_args(connection : Connection) -> Array[String] {
  [
    "-X",
    "-v",
    "ON_ERROR_STOP=1",
    "-A",
    "-t",
    "-F",
    "|",
    "-h",
    connection.host,
    "-p",
    connection.port,
    "-U",
    connection.user,
    "-d",
    connection.database,
  ]
}

///|
async fn run(
  connection : Connection,
  suffix : Array[String],
) -> String raise PostgresError {
  let process = @spawn.spawn(
    connection.psql,
    suffix.map(fn(value) { value.to_string_view() }),
    timeout=120_000,
  ) catch {
    error => raise PostgresError::Process("\{to_repr(error)}")
  }
  let status = process_status(process)
  if status != 0 {
    let detail = process_text(process, "stderr")
    raise PostgresError::Failed(
      if detail.is_empty() {
        let stdout = process_text(process, "stdout")
        if stdout.is_empty() {
          "psql failed"
        } else {
          stdout.trim().to_owned()
        }
      } else {
        detail.trim().to_owned()
      },
    )
  } else {
    process_text(process, "stdout")
  }
}

///|
pub async fn run_sql(
  connection : Connection,
  sql : String,
) -> String raise PostgresError {
  let arguments = command_args(connection)
  arguments.append(["-c", sql])
  run(connection, arguments)
}

///|
pub async fn run_file(
  connection : Connection,
  path : String,
) -> String raise PostgresError {
  let arguments = command_args(connection)
  arguments.append(["-f", path])
  run(connection, arguments)
}

///|
pub fn sql_literal(value : String) -> String {
  "'" +
  value.split("'").map(fn(part) { part.to_owned() }).to_array().join("''") +
  "'"
}
