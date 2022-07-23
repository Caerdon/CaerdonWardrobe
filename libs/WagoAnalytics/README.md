In your plugin's pkgmeta file, add the following:

```
externals:
  libs/WagoAnalytics:
    url: https://github.com/methodgg/WagoAnalytics.git
    branch: main
```

And in your toc file, add the following:
```
## OptionalDependencies: WagoAnalytics

libs/WagoAnalytics/Shim.lua
```