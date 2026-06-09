package bundle

func stripJSONComments(source []byte) []byte {
	output := make([]byte, 0, len(source))
	inString := false
	escaped := false
	inLineComment := false
	inBlockComment := false

	for index := 0; index < len(source); index++ {
		char := source[index]
		var next byte
		if index+1 < len(source) {
			next = source[index+1]
		}

		if inLineComment {
			if char == '\n' || char == '\r' {
				inLineComment = false
				output = append(output, char)
			} else {
				output = append(output, ' ')
			}
			continue
		}

		if inBlockComment {
			if char == '*' && next == '/' {
				output = append(output, ' ', ' ')
				index++
				inBlockComment = false
			} else if char == '\n' || char == '\r' {
				output = append(output, char)
			} else {
				output = append(output, ' ')
			}
			continue
		}

		if inString {
			output = append(output, char)
			if escaped {
				escaped = false
			} else if char == '\\' {
				escaped = true
			} else if char == '"' {
				inString = false
			}
			continue
		}

		if char == '"' {
			inString = true
			output = append(output, char)
		} else if char == '/' && next == '/' {
			output = append(output, ' ', ' ')
			index++
			inLineComment = true
		} else if char == '/' && next == '*' {
			output = append(output, ' ', ' ')
			index++
			inBlockComment = true
		} else {
			output = append(output, char)
		}
	}

	return output
}
