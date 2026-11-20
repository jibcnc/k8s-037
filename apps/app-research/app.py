import os
import tempfile

from flask import Flask, redirect, render_template, request

app = Flask(__name__)

DATA_DIR = os.environ.get("DATA_DIR", "/data")
DATA_FILE = os.path.join(DATA_DIR, "research.txt")
DEFAULT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "default-research.txt")


def load_text():
    path = DATA_FILE if os.path.exists(DATA_FILE) else DEFAULT_FILE
    with open(path, encoding="utf-8") as f:
        return f.read()


def save_text(text):
    # Write to a temp file, then rename it, so the 2 replicas never read a half-written file
    fd, tmp = tempfile.mkstemp(dir=DATA_DIR, prefix=".research-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, DATA_FILE)


@app.route("/research")
@app.route("/research/")
def research():
    return render_template("research.html", text=load_text())


@app.route("/")
def admin_root():
    # admin.id-037.com/ opens the edit page directly
    return redirect("/edit")


@app.route("/edit", methods=["GET", "POST"])
def edit():
    if request.method == "POST":
        save_text(request.form.get("text", ""))
        return redirect("/edit?saved=1")
    return render_template("edit.html", text=load_text(), saved=request.args.get("saved") == "1")


@app.route("/healthz")
def healthz():
    return "ok", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
