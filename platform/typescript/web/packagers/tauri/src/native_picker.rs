use std::{
    collections::HashMap,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::PathBuf,
    thread,
};

use crate::child_process_path;

pub(crate) fn start_native_picker_listener(listener: TcpListener) {
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            thread::spawn(move || {
                handle_native_picker_request(stream);
            });
        }
    });
}

fn handle_native_picker_request(mut stream: TcpStream) {
    let mut buffer = [0; 4096];
    let count = stream.read(&mut buffer).unwrap_or(0);
    let request = String::from_utf8_lossy(&buffer[..count]);
    let Some(target) = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
    else {
        write_json_response(
            &mut stream,
            400,
            serde_json::json!({"error": "Invalid request"}),
        );
        return;
    };
    let Some(query) =
        target
            .strip_prefix("/pick?")
            .or_else(|| if target == "/pick" { Some("") } else { None })
    else {
        write_json_response(&mut stream, 404, serde_json::json!({"error": "Not found"}));
        return;
    };
    let values = parse_query(query);
    let kind = values.get("kind").map(String::as_str).unwrap_or("file");
    let title = values
        .get("title")
        .map(String::as_str)
        .unwrap_or(if kind == "directory" {
            "Choose directory"
        } else {
            "Choose file"
        });
    let default_path = values.get("defaultPath").map(String::as_str).unwrap_or("");
    match pick_native_path(kind, title, default_path) {
        Ok(Some(path)) => write_json_response(
            &mut stream,
            200,
            serde_json::json!({"path": child_process_path(&path), "kind": kind, "cancelled": false}),
        ),
        Ok(None) => write_json_response(
            &mut stream,
            200,
            serde_json::json!({"kind": kind, "cancelled": true}),
        ),
        Err(error) => write_json_response(
            &mut stream,
            400,
            serde_json::json!({"error": error.to_string()}),
        ),
    }
}

fn pick_native_path(
    kind: &str,
    title: &str,
    default_path: &str,
) -> Result<Option<PathBuf>, Box<dyn std::error::Error>> {
    let mut dialog = rfd::FileDialog::new().set_title(title);
    if !default_path.is_empty() {
        dialog = dialog.set_directory(default_path);
    }
    match kind {
        "directory" | "folder" => Ok(dialog.pick_folder()),
        "file" => Ok(dialog.pick_file()),
        _ => Err("Path picker kind must be file or directory.".into()),
    }
}

fn parse_query(query: &str) -> HashMap<String, String> {
    query
        .split('&')
        .filter(|part| !part.is_empty())
        .filter_map(|part| {
            let (key, value) = part.split_once('=').unwrap_or((part, ""));
            Some((percent_decode(key)?, percent_decode(value)?))
        })
        .collect()
}

fn percent_decode(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                output.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).ok()?;
                output.push(u8::from_str_radix(hex, 16).ok()?);
                index += 3;
            }
            byte => {
                output.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8(output).ok()
}

fn write_json_response(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "Internal Server Error",
    };
    let payload = format!("{body}\n");
    let response = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{payload}",
        payload.len()
    );
    let _ = stream.write_all(response.as_bytes());
}
