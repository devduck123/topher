import XCTest

@testable import TopherCore

final class HTTPSDomainTests: XCTestCase {
  func testNormalizesAValidatedPublicDomainToHTTPS() throws {
    let domain = try XCTUnwrap(HTTPSDomain("HTTPS://Developer.Apple.com"))

    XCTAssertEqual(domain.host, "developer.apple.com")
    XCTAssertEqual(domain.url.absoluteString, "https://developer.apple.com/")
  }

  func testAcceptsCommonPublicDomainShapes() {
    let cases = ["tnc.com", "www.swift.org", "docs.github.io", "x-y.co.uk"]

    for value in cases {
      XCTAssertNotNil(HTTPSDomain(value), value)
    }
  }

  func testRejectsValuesOutsideTheBoundedHTTPSDomainGrammar() {
    let cases = [
      "",
      "localhost",
      "http://example.com",
      "ftp://example.com",
      "example.com/path",
      "example.com?query=private",
      "example.com#fragment",
      "user@example.com",
      "example.com:443",
      "127.0.0.1",
      "-bad.com",
      "bad-.com",
      "bad..com",
      "totally-real.example",
      "name.test",
    ]

    for value in cases {
      XCTAssertNil(HTTPSDomain(value), value)
    }
  }
}
