#!/usr/bin/env python3
"""
vmctl.py — Centre de contrôle de l'environnement VM-ARENA
==========================================================
Pilote les 3 éléments sans jamais éditer de fichier à la main :
  • CONTROL PLANE : ce repo Git (état, files, snapshots)
  • NODE "action"    : VM GitHub Actions 4c/16 Go (éphémère, snapshot Git)
  • NODE "codespace" : Codespace 4c/16 Go (disque persistant, via PAT)

USAGE
-----
  python3 vmctl.py status                     # état des 3 éléments
  python3 vmctl.py runs                       # historique des exécutions
  python3 vmctl.py out                        # dernier résultat publié
  python3 vmctl.py run action "echo salut"    # exécute sur la VM Actions
  python3 vmctl.py run codespace "hostname"   # exécute sur le Codespace
  python3 vmctl.py run action --file task.sh  # tâche depuis un fichier
  python3 vmctl.py policy stop|keep           # arrêt du Codespace après tâche
  python3 vmctl.py engine "commande"          # raccourci: tâche sur l'état persistant (~/persist de la VM Actions)

Une mission = un commit → déclenche le workflow → la VM exécute →
le résultat est publié dans bridge/out.txt puis affiché ici.
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.abspath(__file__))
BRANCH = "arena/01a061e4-vm-arena"
WORKFLOW = "vm-bridge.yml"
OUT = "bridge/out.txt"
MAX_RUN_MINUTES = 35


def sh(cmd, cwd=REPO, capture=True, check=False):
    r = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str),
                       capture_output=capture, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"échec: {cmd}\n{r.stderr}")
    return r


def git(*args, check=True):
    return sh(["git", *args], check=check)


def gh(*args, check=True):
    return sh(["gh", *args], check=check)


def sync():
    """Aligne le dépôt local sur la branche distante."""
    git("fetch", "origin", f"refs/heads/{BRANCH}:refs/remotes/origin/{BRANCH}", "-q", check=False)
    git("reset", "--hard", f"origin/{BRANCH}", "-q")


def read(p, default=""):
    full = os.path.join(REPO, p)
    return open(full).read().strip() if os.path.exists(full) else default


# ---------------------------------------------------------------- status
def cmd_status(_):
    sync()
    print("════════ ÉTAT VM-ARENA ════════")
    print(f"repo     : aligné sur origin/{BRANCH} @ {git('rev-parse','--short','HEAD').stdout.strip()}")
    snap = os.path.join(REPO, "bridge/state/snapshot.tar.gz")
    if os.path.exists(snap):
        print(f"snapshot : {os.path.getsize(snap)//1024} Ko (état persistant du node ACTION)")
    else:
        print("snapshot : absent (première session)")
    last_out = read(OUT)
    if last_out:
        print(f"dernière sortie : {len(last_out)} caractères — `python3 vmctl.py out` pour tout voir")
    print("\n── dernières exécutions ──")
    r = gh("run", "list", f"--workflow={WORKFLOW}", "--limit", "3",
           "--json", "displayTitle,status,conclusion,createdAt,databaseId", check=False)
    if r.returncode == 0:
        for run in json.loads(r.stdout or "[]"):
            print(f"  #{run['databaseId']} [{run['status']}/{run.get('conclusion') or '—'}] "
                  f"{run['createdAt'][:16]}  {run['displayTitle'][:60]}")
    print("\n── codespace ──")
    print("  (l'état live demande une tâche : `python3 vmctl.py run codespace hostname`)")


def cmd_runs(_):
    r = gh("run", "list", f"--workflow={WORKFLOW}", "--limit", "15",
           "--json", "displayTitle,status,conclusion,createdAt,duration,databaseId", check=False)
    for run in (json.loads(r.stdout or "[]") if r.returncode == 0 else []):
        print(f"#{run['databaseId']} [{run['status']}/{run.get('conclusion') or '—'}] "
              f"{run.get('duration') or '?'}  {run['displayTitle'][:70]}")


def cmd_out(_):
    sync()
    out = read(OUT)
    print(out if out else "(aucune sortie publiée)")
    art = os.path.join(REPO, "bridge/artifacts")
    if os.path.isdir(art):
        files = [f for f in os.listdir(art) if not f.startswith(".")]
        if files:
            print(f"\n── artifacts ({len(files)}) ──: {', '.join(files[:10])}")


def cmd_policy(args):
    sync()
    p = f"bridge/codespace_policy.txt"
    open(os.path.join(REPO, p), "w").write(args.value + "\n")
    git("add", p)
    git("-c", "user.name=vmctl", "-c", "user.email=vmctl@local",
        "commit", "-q", "-m", f"vmctl: politique codespace = {args.value}")
    git("push", "-q", "origin", BRANCH)
    print(f"✅ politique d'arrêt du Codespace : {args.value}")


# ---------------------------------------------------------------- run
def find_run(sha, timeout=90):
    """Attend et retourne le run GitHub correspondant au commit sha."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r = gh("run", "list", f"--workflow={WORKFLOW}", "--limit", "10",
               "--json", "databaseId,headSha,status", check=False)
        if r.returncode == 0:
            for run in json.loads(r.stdout or "[]"):
                if run.get("headSha", "").startswith(sha):
                    return run["databaseId"]
        time.sleep(6)
    return None


def wait_run(run_id):
    t0 = time.time()
    while time.time() - t0 < MAX_RUN_MINUTES * 60:
        r = gh("run", "view", str(run_id), "--json", "status,conclusion", check=False)
        if r.returncode == 0:
            d = json.loads(r.stdout or "{}")
            if d.get("status") == "completed":
                return d.get("conclusion")
        el = int(time.time() - t0)
        print(f"  ⏳ en cours… {el//60}m{el%60:02d}s", end="\r", flush=True)
        time.sleep(10)
    return "timeout"


def cmd_run(args):
    sync()
    tid = f"{dt.datetime.utcnow():%m%d-%H%M%S}-{args.target}"
    script = open(args.file).read() if args.file else args.command
    if not script or not script.strip():
        sys.exit("❌ tâche vide")
    open(os.path.join(REPO, "bridge/task.sh"), "w").write(script if script.endswith("\n") else script + "\n")
    open(os.path.join(REPO, "bridge/target.txt"), "w").write(args.target + "\n")
    open(os.path.join(REPO, "bridge/task_id.txt"), "w").write(tid + "\n")

    # le marqueur fait varier cmd.txt → garantit le déclenchement du workflow
    marker_path = os.path.join(REPO, "bridge/cmd.txt")
    marker = f"# pilot: vmctl {tid}\n"
    content = open(marker_path).read()
    if "# pilot: vmctl" in content:
        lines = [l for l in content.splitlines(True) if not l.startswith("# pilot: vmctl")]
        content = "".join(lines) + marker
    else:
        content += marker
    open(marker_path, "w").write(content)

    git("add", "bridge/task.sh", "bridge/target.txt", "bridge/task_id.txt", "bridge/cmd.txt")

    def pull_rebase():
        git("fetch", "origin", f"refs/heads/{BRANCH}:refs/remotes/origin/{BRANCH}", "-q", check=False)
        return git("rebase", f"origin/{BRANCH}", "-q", check=False)

    pull_rebase()
    git("-c", "user.name=vmctl", "-c", "user.email=vmctl@local",
        "commit", "-q", "-m", f"vmctl: tâche {tid}")
    for _ in range(5):
        if git("push", "-q", "origin", BRANCH, check=False).returncode == 0:
            break
        pull_rebase()
    else:
        sys.exit("❌ push impossible")
    sha = git("rev-parse", "--short=8", "HEAD").stdout.strip()
    print(f"🚀 tâche {tid} poussée ({sha}) — cible : {args.target}")

    run_id = find_run(sha)
    if not run_id:
        sys.exit("❌ aucun run GitHub détecté pour ce commit")
    print(f"   run #{run_id}")
    conclusion = wait_run(run_id)
    print(f"\n   conclusion : {conclusion}")

    sync()
    out = read(OUT)
    print("\n" + (out if out else "(aucune sortie publiée)"))
    if conclusion not in ("success", None):
        print("\n⚠️ le run a échoué — voir: gh run view", run_id, "--log-failed")


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Centre de contrôle VM-ARENA")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("runs").set_defaults(fn=cmd_runs)
    sub.add_parser("out").set_defaults(fn=cmd_out)
    p_pol = sub.add_parser("policy")
    p_pol.add_argument("value", choices=["stop", "keep"])
    p_pol.set_defaults(fn=cmd_policy)
    p_run = sub.add_parser("run")
    p_run.add_argument("target", choices=["action", "codespace"])
    p_run.add_argument("command", nargs="?", help="commande ou script shell")
    p_run.add_argument("--file", help="tâche depuis un fichier")
    p_run.set_defaults(fn=cmd_run)
    args = ap.parse_args()

    # raccourci : engine = run action avec cd ~/persist implicite (état persistant)
    if args.cmd == "run" and args.target == "action" and args.command and args.command.startswith("engine:"):
        args.command = args.command.replace("engine:", "", 1).strip()

    args.fn(args)


if __name__ == "__main__":
    main()
