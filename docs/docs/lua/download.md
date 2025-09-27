# Download API

The download API allows Lua scripts to trigger file downloads from URLs.

## gurt.download

Downloads a file from a URL and saves it to the user's default download location.

### Syntax

```lua
download_id = gurt.download(url filename)
```

### Parameters

- **url** (string): The URL to download from. Supports HTTP, HTTPS, and gurt:// protocols.
- **filename** (string, optional): The filename to save as. If not provided, the filename will be extracted from the URL or default to "download".

### Returns

- **download_id** (string): A unique identifier for the download operation.
