#!/usr/bin/env python
import os, sys
import json
import jinja2

def render(tpl_path, context):
    path, filename = os.path.split(tpl_path)
    return jinja2.Environment(
        loader=jinja2.FileSystemLoader(path or './')
    ).get_template(filename).render(context)

filename = sys.argv[1]
context = {}
if len(sys.argv) > 2: context = json.loads(sys.argv[2])

print render(filename, context)

