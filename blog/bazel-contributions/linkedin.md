Three of my changes are now merged into Bazel.

→ exclusive-if-local tests now run in parallel under remote execution. 12 tests went from 61.9s to 5.6s. Tests that have to run locally are still serialized.

→ Build without the Bytes no longer re-runs actions after an IDE-style --remote_download_outputs=all build. A no-op rebuild went from 2,000 remote cache hits to 0.

→ bazel query --output=streamed_proto can now serialize in parallel (--experimental_parallel_streamed_proto_output). 100k targets went from 2.24s to 0.89s on 4 cores, with byte-identical output.

Every number is a before/after measurement on the same machine, and the scripts are published.

Full write-up: <BLOG_URL>

#Bazel #BuildSystems #OpenSource
