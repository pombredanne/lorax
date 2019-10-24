#
# Copyright (C) 2017-2019 Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
import logging
log = logging.getLogger("lorax-composer")

from collections import namedtuple
from flask import Flask, jsonify, redirect, send_from_directory
from glob import glob
import os
import werkzeug

from pylorax import vernum
from pylorax.api.errors import HTTP_ERROR
from pylorax.api.v0 import v0_api
from pylorax.api.v1 import v1_api
from pylorax.sysutils import joinpaths

GitLock = namedtuple("GitLock", ["repo", "lock", "dir"])

server = Flask(__name__)

__all__ = ["server", "GitLock"]

@server.route('/')
def server_root():
    redirect("/api/docs/")

@server.route("/api/docs/")
@server.route("/api/docs/<path:path>")
def api_docs(path=None):
    # Find the html docs
    try:
        # This assumes it is running from the source tree
        docs_path = os.path.abspath(joinpaths(os.path.dirname(__file__), "../../../docs/html"))
    except IndexError:
        docs_path = glob("/usr/share/doc/lorax-*/html/")[0]

    if not path:
        path="index.html"
    return send_from_directory(docs_path, path)

@server.route("/api/status")
def api_status():
    """
    `/api/status`
    ^^^^^^^^^^^^^^^^
    Return the status of the API Server::

          { "api": "0",
            "build": "devel",
            "db_supported": true,
            "db_version": "0",
            "schema_version": "0",
            "backend": "lorax-composer",
            "msgs": []}

    The 'msgs' field can be a list of strings describing startup problems or status that
    should be displayed to the user. eg. if the compose templates are not depsolving properly
    the errors will be in 'msgs'.
    """
    return jsonify(backend="lorax-composer",
                   build=vernum,
                   api="1",
                   db_version="0",
                   schema_version="0",
                   db_supported=True,
                   msgs=server.config["TEMPLATE_ERRORS"])

@server.errorhandler(werkzeug.exceptions.HTTPException)
def bad_request(error):
    return jsonify(status=False, errors=[{ "id": HTTP_ERROR, "code": error.code, "msg": error.name }]), error.code

# Register the v0 API on /api/v0/
server.register_blueprint(v0_api, url_prefix="/api/v0/")

# Register the v1 API on /api/v1/
# Use v0 routes by default
skip_rules = [
    "/compose",
    "/compose/queue",
    "/compose/finished",
    "/compose/failed",
    "/compose/status/<uuids>",
    "/compose/info/<uuid>",
    "/projects/source/info/<source_names>",
    "/projects/source/new",
]
server.register_blueprint(v0_api, url_prefix="/api/v1/", skip_rules=skip_rules)
server.register_blueprint(v1_api, url_prefix="/api/v1/")
