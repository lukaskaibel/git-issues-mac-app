# Security

The app handles a GitHub access token, so security reports are taken seriously.

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/lukaskaibel/issues-for-github/security/advisories/new)
rather than in a public issue. You will get a reply as soon as possible.

What the app does with your token: it is kept in the macOS keychain (or read from the GitHub CLI when you chose
that option) and sent only to `api.github.com` and, during OAuth sign-in, `github.com`.
