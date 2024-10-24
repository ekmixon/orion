# coding=utf-8
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
"""Common definitions for Grizzly reduction in Taskcluster
"""

import json
from abc import ABC, abstractmethod
from argparse import ArgumentParser
from functools import wraps
from logging import DEBUG, INFO, WARNING, basicConfig
from pathlib import Path

from Reporter.Reporter import Reporter
from taskcluster.helper import TaskclusterConfig

# Shared taskcluster configuration
Taskcluster = TaskclusterConfig("https://community-tc.services.mozilla.com")


def remote_checks(wrapped):
    """Decorator to perform error checks before using remote features"""

    @wraps(wrapped)
    def decorator(self, *args, **kwargs):
        if not self.serverProtocol:
            raise RuntimeError(
                "Must specify serverProtocol (configuration property: serverproto) to "
                "use remote features."
            )
        if not self.serverPort:
            raise RuntimeError(
                "Must specify serverPort (configuration property: serverport) to use "
                "remote features."
            )
        if not self.serverHost:
            raise RuntimeError(
                "Must specify serverHost (configuration property: serverhost) to use "
                "remote features."
            )
        if not self.serverAuthToken:
            raise RuntimeError(
                "Must specify serverAuthToken (configuration property: "
                "serverauthtoken) to use remote features."
            )
        return wrapped(self, *args, **kwargs)

    return decorator


class CommonArgParser(ArgumentParser):
    """Argument parser with common arguments used by reduction scripts."""

    def __init__(self, *args, **kwds):
        super().__init__(*args, **kwds)
        group = self.add_mutually_exclusive_group()
        group.add_argument(
            "--quiet",
            "-q",
            dest="log_level",
            action="store_const",
            const=WARNING,
            help="Be less verbose",
        )
        group.add_argument(
            "--verbose",
            "-v",
            dest="log_level",
            action="store_const",
            const=DEBUG,
            help="Be more verbose",
        )
        self.set_defaults(log_level=INFO)


class CrashManager(Reporter):
    """Class to manage access to CrashManager server."""

    @remote_checks
    def _list_objs(self, endpoint, query=None, ordering=None):
        params = {}
        if query is not None:
            params["query"] = json.dumps(query)
        if ordering is not None:
            params["ordering"] = ",".join(ordering)

        next_url = (
            f"{self.serverProtocol}://{self.serverHost}:{self.serverPort}"
            f"/crashmanager/rest/{endpoint}/"
        )

        while next_url:

            resp_json = self.get(next_url, params=params).json()

            if not isinstance(resp_json, dict):
                raise RuntimeError(
                    f"Server sent malformed JSON response: {resp_json!r}"
                )

            next_url = resp_json["next"]
            params = None

            yield from resp_json["results"]

    def list_crashes(self, query=None, ordering=None):
        """List all CrashEntry objects.

        Arguments:
            query (dict or None): The query definition to use.
                                  (see crashmanager.views.json_to_query)
            ordering (list or None): Field(s) to order by (eg. `id` or `-id`)

        Yields:
            dict: Dict representation of CrashEntry
        """
        yield from self._list_objs("crashes", query=query, ordering=ordering)

    def list_buckets(self, query=None):
        """List all Bucket objects.

        Arguments:
            query (dict or None): The query definition to use.
                                  (see crashmanager.views.json_to_query)

        Yields:
            dict: Dict representation of Bucket
        """
        yield from self._list_objs("buckets", query=query)

    @remote_checks
    def update_testcase_quality(self, crash_id, testcase_quality):
        """Update a CrashEntry's testcase quality.

        Arguments:
            crash_id (int): Crash ID to update.
            testcase_quality (int): Testcase quality to set.

        Returns:
            None
        """
        url = (
            f"{self.serverProtocol}://{self.serverHost}:{self.serverPort}"
            f"/crashmanager/rest/crashes/{crash_id}/"
        )
        self.patch(url, data={"testcase_quality": testcase_quality})


class ReductionWorkflow(ABC):
    """Common framework for reduction scripts."""

    @abstractmethod
    def run(self):
        """Run the actual reduction script.
        Any necessary parameters must be set on the instance in `from_args`/`__init__`.

        Returns:
            int: Return code (0 for success)
        """

    @staticmethod
    @abstractmethod
    def parse_args(args=None):
        """Parse CLI arguments and return the parsed result.

        This should used `CommonArgParser` to ensure the default arguments exist for
        compatibility with `main`.

        Arguments:
            args (list or None): Arguments list from shell (None for sys.argv).

        Returns:
            argparse.Namespace: Parsed args.
        """

    @classmethod
    @abstractmethod
    def from_args(cls, args):
        """Create an instance from parsed args.

        Arguments:
            args (argparse.Namespace): Parsed args.

        Returns:
            cls: Returns an initialized instance.
        """

    @staticmethod
    def ensure_credentials():
        """Ensure necessary credentials exist for reduction scripts.

        This checks:
            ~/.fuzzmanagerconf  -- fuzzmanager credentials

        Returns:
            None
        """
        # get fuzzmanager config from taskcluster
        conf_path = Path.home() / ".fuzzmanagerconf"
        if not conf_path.is_file():
            key = Taskcluster.load_secrets("project/fuzzing/fuzzmanagerconf")["key"]
            conf_path.write_text(key)
            conf_path.chmod(0o400)

    @classmethod
    def main(cls, args=None):
        """Main entrypoint for reduction scripts.

        Returns:
            int:
        """
        if args is None:
            args = cls.parse_args()

        # Setup logger
        basicConfig(level=args.log_level)

        # Setup credentials if needed
        cls.ensure_credentials()

        return cls.from_args(args).run()
