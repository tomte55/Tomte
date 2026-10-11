"""Loads DB2 tables as CSV exports from wago.tools for tools/events.py and tools/waynet.py (stdlib only).

Both scripts run with `python -I`, which leaves the script folder off sys.path, so they insert tools/ themselves
before importing this module.
"""
import csv
import os
import sys
import tempfile
import urllib.request

# wago.tools refuses downloads that don't look like a browser.
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0 Safari/537.36")


def load(folder, tables, build, user_agent=True):
    """Rows of each table as a list of dicts, { name: rows }. A table missing from `folder` is downloaded there."""
    data = {}
    for name in tables:
        path = os.path.join(folder, name + ".csv")
        if not os.path.exists(path):
            url = "https://wago.tools/db2/%s/csv?build=%s" % (name, build)
            print("downloading", url)
            req = urllib.request.Request(url, headers={"User-Agent": UA} if user_agent else {})
            with urllib.request.urlopen(req) as resp, open(path, "wb") as f:
                f.write(resp.read())
        with open(path, encoding="utf-8") as f:
            data[name] = list(csv.DictReader(f))
    return data


def folder_from_argv(prefix):
    """The CSV folder from the second command line argument, or a new temp folder named after `prefix`."""
    return sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp(prefix=prefix)
