use std::collections::HashMap;
use std::fmt;
use std::fs::OpenOptions;
use std::io::{self, BufRead, Write};
use std::process::{Command, Stdio};

use process_wrapper::output::{process_output, LineOutput};
use process_wrapper::rustc::ErrorFormat;
use process_wrapper::tinyjson::JsonValue;

use crate::cache::IncrementalCache;

#[derive(Debug)]
pub struct WorkerError(pub String);

impl fmt::Display for WorkerError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "worker error: {}", self.0)
    }
}

struct WorkRequest {
    arguments: Vec<String>,
    request_id: i64,
}

struct WorkResponse {
    exit_code: i32,
    output: String,
    request_id: i64,
}

fn parse_work_request(line: &str) -> Result<WorkRequest, WorkerError> {
    let parsed: JsonValue = line
        .parse()
        .map_err(|_| WorkerError("failed to parse WorkRequest JSON".into()))?;

    let obj = match &parsed {
        JsonValue::Object(m) => m,
        _ => return Err(WorkerError("WorkRequest is not a JSON object".into())),
    };

    let arguments = match obj.get("arguments") {
        Some(JsonValue::Array(arr)) => arr
            .iter()
            .map(|v| match v {
                JsonValue::String(s) => Ok(s.clone()),
                _ => Err(WorkerError("argument is not a string".into())),
            })
            .collect::<Result<Vec<_>, _>>()?,
        _ => vec![],
    };

    let request_id = match obj.get("requestId") {
        Some(JsonValue::Number(n)) => *n as i64,
        _ => 0,
    };

    Ok(WorkRequest {
        arguments,
        request_id,
    })
}

fn serialize_work_response(resp: &WorkResponse) -> String {
    let mut obj = HashMap::new();
    obj.insert(
        "exitCode".to_string(),
        JsonValue::Number(resp.exit_code as f64),
    );
    obj.insert(
        "output".to_string(),
        JsonValue::String(resp.output.clone()),
    );
    obj.insert(
        "requestId".to_string(),
        JsonValue::Number(resp.request_id as f64),
    );
    JsonValue::Object(obj)
        .stringify()
        .unwrap_or_else(|_| "{}".to_string())
}

fn process_line(
    line: String,
    quit_on_rmeta: bool,
    format: ErrorFormat,
    metadata_emitted: &mut bool,
) -> Result<LineOutput, String> {
    if quit_on_rmeta {
        process_wrapper::rustc::stop_on_rmeta_completion(line, format, metadata_emitted)
    } else {
        process_wrapper::rustc::process_json(line, format)
    }
}

fn handle_request(
    req: &WorkRequest,
    cache: &mut IncrementalCache,
) -> WorkResponse {
    let opts = match process_wrapper::options::options_from_args(req.arguments.clone()) {
        Ok(o) => o,
        Err(e) => {
            return WorkResponse {
                exit_code: 1,
                output: format!("Failed to parse options: {}", e),
                request_id: req.request_id,
            };
        }
    };

    let cache_dir = cache.get_or_create(&opts.child_arguments);
    let mut child_args = opts.child_arguments.clone();

    if let Some(dir) = &cache_dir {
        child_args.push(format!("-Cincremental={}", dir.display()));
    }

    let mut command = Command::new(&opts.executable);
    command
        .args(&child_args)
        .env_clear()
        .envs(&opts.child_environment)
        .stdout(if let Some(ref stdout_file) = opts.stdout_file {
            OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .open(stdout_file)
                .map(Into::into)
                .unwrap_or(Stdio::inherit())
        } else {
            Stdio::inherit()
        })
        .stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(c) => c,
        Err(e) => {
            return WorkResponse {
                exit_code: 1,
                output: format!("Failed to spawn child process: {}", e),
                request_id: req.request_id,
            };
        }
    };

    let mut stderr_buf = Vec::new();
    let mut child_stderr = child.stderr.take().unwrap();
    let mut was_killed = false;

    if let Some(format) = opts.rustc_output_format {
        let quit_on_rmeta = opts.rustc_quit_on_rmeta;
        let mut me = false;
        let metadata_emitted = &mut me;
        let _ = process_output(
            &mut child_stderr,
            &mut stderr_buf,
            None,
            move |line| process_line(line, quit_on_rmeta, format, metadata_emitted),
        );
        if me {
            let _ = child.kill();
            was_killed = true;
        }
    } else {
        let _ = io::copy(&mut child_stderr, &mut stderr_buf);
    }

    let status = match child.wait() {
        Ok(s) => s,
        Err(e) => {
            return WorkResponse {
                exit_code: 1,
                output: format!("Failed to wait for child: {}", e),
                request_id: req.request_id,
            };
        }
    };

    let code = if was_killed {
        0
    } else {
        status.code().unwrap_or(1)
    };

    if code == 0 {
        if let Some(ref tf) = opts.touch_file {
            let _ = OpenOptions::new().create(true).truncate(true).write(true).open(tf);
        }
        if let Some((ref src, ref dst)) = opts.copy_output {
            let _ = std::fs::copy(src, dst);
        }
    } else if cache_dir.is_some() {
        cache.invalidate(&opts.child_arguments);
    }

    WorkResponse {
        exit_code: code,
        output: String::from_utf8_lossy(&stderr_buf).into_owned(),
        request_id: req.request_id,
    }
}

pub fn run_worker_loop() -> Result<(), WorkerError> {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut cache = IncrementalCache::new();

    for line in stdin.lock().lines() {
        let line = line.map_err(|e| WorkerError(format!("stdin read error: {}", e)))?;
        if line.is_empty() {
            continue;
        }

        let req = parse_work_request(&line)?;
        let resp = handle_request(&req, &mut cache);
        let resp_json = serialize_work_response(&resp);

        writeln!(stdout, "{}", resp_json)
            .map_err(|e| WorkerError(format!("stdout write error: {}", e)))?;
        stdout
            .flush()
            .map_err(|e| WorkerError(format!("stdout flush error: {}", e)))?;
    }

    Ok(())
}
