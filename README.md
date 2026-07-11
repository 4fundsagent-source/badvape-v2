# BadVape

BadVape uses a workspace base runtime and a separately protected game module.
The domain loader downloads only the explicit files in `public-manifest.json`
when the workspace is missing. Later runs reuse that cache and fetch only
repairs or a new manifest revision. User profiles are preserved, and the
licensing server never stores or sends runtime files.

The customer entrypoint is:

```lua
loadstring(game:HttpGet 'https://luvit.cc')() {
    log { "YOUR-LICENSE-KEY" }
}
```

The loader only forwards the credential into the workspace runtime. For
protected places, `main.lua` invokes `games/protected6872274481.lua`, where the
production authorization check and game module live together. If that file is
missing or authorization fails, the public UI and universal modules still load.

`games/6872274481.lua`, authentication server source, build tooling, and release
keys are never published. `games/protected6872274481.lua` is the reviewed
encrypted artifact used by protected places.
