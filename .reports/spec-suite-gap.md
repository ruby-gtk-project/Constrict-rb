# Spec suite: no examples, dev-shell gem gap

Running the dev-shell banner's spec command:

```
nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

fails to load `spec/spec_helper.rb`:

```
Failure/Error: require "kettle/test/rspec"
LoadError: cannot load such file -- kettle/test/rspec
```

`kettle-test` is declared as a development dependency in `constrict-rb.gemspec`
(the kettle-jem scaffold boilerplate shared across this fleet), but it is not
vendored into the Nix dev shell's Ruby package set, so the `require` fails
before any example runs.

This is not a port bug: `spec/` contains only the kettle-jem scaffold
(`spec_helper.rb`, `README.md`) and zero `*_spec.rb` files, so there is no
test content this gap is hiding — "0 examples, 2 errors occurred outside of
examples" either way. The real functional coverage for this port is
`test/drive_constrict.rb` (150 checks, all passing, `DRIVE OK`), which is the
harness this round's gate relies on.

Not fixed here: pulling `kettle-test` into the flake would mean vendoring (or
building from source) a gem this app's own dependency tree does not install,
purely to satisfy an empty scaffold directory, which is outside the scope of
proving the GTK port runs.
