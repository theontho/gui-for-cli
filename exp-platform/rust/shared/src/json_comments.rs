pub fn strip_json_comments(source: &str) -> String {
    let chars: Vec<char> = source.chars().collect();
    let mut output = String::with_capacity(source.len());
    let mut in_string = false;
    let mut escaped = false;
    let mut in_line_comment = false;
    let mut in_block_comment = false;
    let mut index = 0;

    while index < chars.len() {
        let char = chars[index];
        let next = chars.get(index + 1).copied();

        if in_line_comment {
            if matches!(char, '\n' | '\r') {
                in_line_comment = false;
                output.push(char);
            } else {
                output.push(' ');
            }
            index += 1;
            continue;
        }

        if in_block_comment {
            if char == '*' && next == Some('/') {
                output.push_str("  ");
                index += 2;
                in_block_comment = false;
            } else {
                output.push(if matches!(char, '\n' | '\r') {
                    char
                } else {
                    ' '
                });
                index += 1;
            }
            continue;
        }

        if in_string {
            output.push(char);
            if escaped {
                escaped = false;
            } else if char == '\\' {
                escaped = true;
            } else if char == '"' {
                in_string = false;
            }
            index += 1;
            continue;
        }

        if char == '"' {
            in_string = true;
            output.push(char);
        } else if char == '/' && next == Some('/') {
            output.push_str("  ");
            index += 1;
            in_line_comment = true;
        } else if char == '/' && next == Some('*') {
            output.push_str("  ");
            index += 1;
            in_block_comment = true;
        } else {
            output.push(char);
        }
        index += 1;
    }

    output
}
