import Foundation
#if os(Windows)
import WinSDK
#endif

public func setEnvironmentVariable(_ key: String, _ value: String?) {
  #if os(Windows)
  key.withCString(encodedAs: UTF16.self) { keyPointer in
    let success = value.map { value in
      value.withCString(encodedAs: UTF16.self) { valuePointer in
        SetEnvironmentVariableW(keyPointer, valuePointer)
      }
    } ?? SetEnvironmentVariableW(keyPointer, nil)
    if !success {
      fatalError("Failed to update environment variable \(key)")
    }
  }
  #else
  let result = value.map { setenv(key, $0, 1) } ?? unsetenv(key)
  if result != 0 {
    fatalError("Failed to update environment variable \(key): errno \(errno)")
  }
  #endif
}
