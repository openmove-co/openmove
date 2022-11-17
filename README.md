# OpenMove

## Build

1. Clone

```sh
git clone git@github.com:openmove-co/openmove.git
```

2. Create a local account `openmove`

```sh
cd openmove
aptos init --profile openmove
```

3. Compile

```sh
aptos move compile --named-addresses openmove=openmove
```

4. Run unit tests

```sh
aptos move test
```

## Usage

Add `address`  and `dependency` to your project's Move.toml

```
[addresses]
openmove = "_" # To be published on chain

[dependencies]
openmove = { git = "https://github.com/openmove-co/openmove.git", rev = "main" }
```