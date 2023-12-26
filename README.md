Yinsh
=====

*(Tuned for local installation)*

An HTML5 version of the board game [Yinsh](http://en.wikipedia.org/wiki/Yinsh) written in [Haskell](http://haskell.org/) / [Haste](http://haste-lang.org/).

[**Play in your browser**](http://david-peter.de/yinsh) (See [Yinsh rules](http://en.wikipedia.org/wiki/Yinsh#Rules))

![Yinsh in browser](https://raw.githubusercontent.com/sharkdp/yinsh/master/info/screenshot.png)

**Install**:
1. Create TLS certificate and private key via e.g. `openssl req -x509 -newkey rsa:4096 -days 365 -keyout ca-key.pem -out ca-cert.pem`
2. Change the configuration at the bottom of `backend/Main.hs` respectively.
3. `cabal run` to start the backend. Open `index.html` to start the front end.
