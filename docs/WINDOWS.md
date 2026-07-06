# Running bluebot on Windows (WSL2)

redroid runs **real Android on the Linux kernel**, so on Windows it must run
inside **WSL2**. The one hard requirement is that the default WSL2 kernel lacks
the Android `binder` driver, so a small custom kernel is built **once**.

## Automatic install (recommended)

Download **[`installer/install.bat`](../installer/install.bat)** and
double-click it (it self-elevates to Administrator). It does everything:

1. Enables WSL2 + installs Ubuntu (reboots once if WSL was not already on —
   just run `install.bat` again after the reboot to resume).
2. Installs Docker inside WSL.
3. Builds a `binder`-enabled WSL2 kernel and points `.wslconfig` at it.
4. Clones the repo and runs `deploy.sh`.
5. Drops a **Bluebot** launcher on your Desktop that starts the panels and opens
   the viewer at `http://localhost:8000`.

The kernel build is the slow step (20–40 min). The installer is idempotent —
re-running skips work that's already done, so it's safe after an interruption.

> One-liner alternative (Administrator PowerShell):
> ```powershell
> irm https://raw.githubusercontent.com/0verdr1v3/bluebot/claude/dreamy-thompson-2rkd15/installer/Install-Bluebot.ps1 | iex
> ```

> Prefer no kernel build at all? A cheap Linux **cloud VM** needs none of this:
> clone, `./deploy.sh`, open the printed URL in your Windows browser.

---

## Manual install (if you'd rather do it yourself, or the installer fails)

## 1. Install WSL2

In an **Administrator PowerShell**:

```powershell
wsl --install -d Ubuntu
wsl --update
```

Reboot if prompted, then open the **Ubuntu** terminal and create your user.

## 2. Install Docker (inside Ubuntu/WSL)

Either install **Docker Desktop for Windows** and enable *Settings → Resources →
WSL integration* for your Ubuntu distro, **or** install Docker Engine directly in
WSL:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"     # log out/in of the WSL shell afterwards
```

Verify: `docker info` should succeed.

## 3. Build a WSL2 kernel with binder (the one-time fiddly bit)

Run this **inside Ubuntu/WSL**:

```bash
sudo apt update
sudo apt install -y build-essential flex bison libssl-dev libelf-dev \
                    bc dwarves git cpio

# Match the branch to your running kernel's major version (uname -r), e.g. 6.6.y
git clone --depth 1 -b linux-msft-wsl-6.6.y \
  https://github.com/microsoft/WSL2-Linux-Kernel.git
cd WSL2-Linux-Kernel

# Start from Microsoft's WSL config, then enable Android binder.
cp Microsoft/config-wsl .config
cat >> .config <<'EOF'
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
EOF
make olddefconfig

# Build (use all cores). Produces arch/x86/boot/bzImage.
make -j"$(nproc)"

# Copy the kernel to your Windows user folder.
cp arch/x86/boot/bzImage /mnt/c/Users/<YOUR_WINDOWS_USERNAME>/bzImage-bluebot
```

> Replace `<YOUR_WINDOWS_USERNAME>`. Check the kernel branch against `uname -r`
> in WSL — if you're on 6.6.x use `linux-msft-wsl-6.6.y`, on 5.15.x use
> `linux-msft-wsl-5.15.y`, etc.

## 4. Tell WSL to use the new kernel

Create `C:\Users\<YOUR_WINDOWS_USERNAME>\.wslconfig` (Windows side) with:

```ini
[wsl2]
kernel=C:\\Users\\<YOUR_WINDOWS_USERNAME>\\bzImage-bluebot
```

Then in **PowerShell**:

```powershell
wsl --shutdown
```

Reopen Ubuntu. Confirm binder is now available:

```bash
zcat /proc/config.gz | grep -i binder      # should show the CONFIG_ANDROID_BINDER* lines
```

## 5. Deploy

Back in Ubuntu/WSL:

```bash
git clone -b claude/dreamy-thompson-2rkd15 https://github.com/0verdr1v3/bluebot.git
cd bluebot
cp .env.example .env
./deploy.sh
```

`deploy.sh` will load binder, pass preflight, build the viewer, and print the
URL. Open **http://localhost:8000** in your Windows browser — WSL2 forwards
`localhost` automatically.

## Troubleshooting

- **doctor.sh still says "binder not loaded"** → the custom kernel isn't active.
  Recheck `.wslconfig` path/escaping, run `wsl --shutdown`, and verify with
  `uname -r` (a custom build usually shows a `-microsoft-...+` suffix) and
  `zcat /proc/config.gz | grep BINDERFS`.
- **`modprobe binder_linux` fails** → that's fine when binder is built *into*
  the kernel (`=y`) rather than as a module; the `/dev/binderfs` check is what
  matters. `setup_host.sh` treats present binder devices as success.
- **Performance is poor** → redroid defaults to software GPU here. GPU
  passthrough into WSL2 for redroid is unreliable; a Linux host/VM with a real
  GPU is the better route if you need many fast panels.
