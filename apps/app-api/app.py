from flask import Flask, render_template

app = Flask(__name__)


@app.route("/api")
@app.route("/api/")
def api_home():
    return render_template("index.html", msg="Usage: /api/<message>")


@app.route("/api/<path:msg>")
def api_message(msg):
    # Jinja2 escapes the text automatically, so HTML in the URL is shown as plain text
    return render_template("index.html", msg=msg)


@app.route("/healthz")
def healthz():
    return "ok", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
