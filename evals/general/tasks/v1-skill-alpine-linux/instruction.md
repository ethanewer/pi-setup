# Alpine Linux fundamentals

Answer four short questions about **Alpine Linux** and its tooling. Base your answers on standard Alpine Linux conventions.

1. What command-line **package manager** does Alpine Linux use (the tool that installs packages with `apk add <pkg>`)? (lowercase)
2. What **C standard-library implementation** does Alpine Linux use as its libc? (lowercase)
3. Which file does Alpine's package manager read at boot to learn which package **repositories** to use (resolve package names from)? Write the **absolute path**.
4. Alpine Linux uses which **init system** (the userspace boot controller that starts services) by default? (lowercase)

Write the four answers to `/app/answer.json`:

```json
{
  "package_manager": "apk",
  "c_library": "musl",
  "repositories_file": "/usr/share/alpine/sys-pkg",
  "init_system": "openrc"
}
```

Replace the values with the correct answers. Every string is checked case-insensitively after trimming. Use only lowercase letters, `_`, `/`, `.` and `-` in your strings.