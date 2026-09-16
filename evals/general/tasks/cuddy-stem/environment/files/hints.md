# Hints

- RFC 6455 section 7.4.1 lists which Close status codes may be sent on the
  wire.  1004, 1005, 1006 and 1015 are reserved there; 1006 exists because
  implementations use it internally when the transport dies without a Close
  frame.

- The reader you drive from /app/reproduce_issue.py is the one the project's
  own parser tests construct: WebSocketDataQueue + WebSocketReader, fed with
  raw frames.  tests/test_websocket_parser.py under /app/src/tests has a
  build_frame / build_close_frame helper you can read (do not modify the
  test files).