<img style="width: 128px; height: 128px" src="site/static/favicon.svg" /><h1 style="font-size: 48px"><a href="https://gurted.com">Gurted</a> - the new ecosystem similar to World Wide Web.</h1>

[Website](https://gurted.com/) | [Docs](https://docs.gurted.com/) | [License](LICENSE) | [YouTube video](https://www.youtube.com)

Gurted is an ecosystem similar to the World Wide Web, it features:
- ⚡ A custom protocol (TCP-based) named `GURT://` with mandatory TLS security with a [spec](docs.gurted.com)
- 🌐 A custom **wayfinder** (browser) written in Rust and GDScript with [Godot](https://godotengine.org/)
- 📄 A custom engine for HTML, CSS, and ***Lua*** (no JavaScript)
- 🏷️ A custom **DNS** that allows users to create domains with TLDs such as `.based`, `.aura`, `.twin`, and many more
- 🔍 A search engine
- 🛠️ A **CLI tool** for setting up GURT protocol servers
- 🔒 A certificate authority (**GurtCA**) for TLS certs on GURT

![snake](https://github.com/user-attachments/assets/d4d10cf2-ff87-4af3-9a38-0ebdc0fadc71)

# File structure
- `/dns` - The **DNS** (Domain Name System)
- `/docs` - The **documentation** at https://docs.gurted.com
- `/flumi` - The **wayfinder** Flumi, used to view gurt:// sites
- `/protocol` - All protocol related things
- `/protocol/library` - The Rust protocol implementation (client + server)
- `/protocol/gdextension` - The Godot extension for GURT protocol (uses Rust library, used in Flumi)
- `/protocol/gurtca` - The **C**ert **A**uthority (CA) for issuing TLS certs
- `/protocol/cli` - The server management tool for GURT protocol servers (Gurty)
- `/search-engine` - The official **search engine** (Ringle)
- `/tests` - The browser test files demonstrating all features
- `/site` - The WWW website (gurted.com)

# Download and install
Go to https://gurted.com/download

# Compiling
The process is identical to compiling a Godot game, however, if you:
1) modified the protocol library
2) the gdextension

...you have to rebuild the GDextension by running build.sh in `/protocol/gdextension` and copy `/addon` to `flumi/addons/gurt-protocol/`.
