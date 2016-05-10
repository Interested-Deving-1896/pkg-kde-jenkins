#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import sys

from junit_xml import TestSuite, TestCase
from pyparsing import (LineStart, Literal, OneOrMore,
                       Regex, SkipTo, Word, ZeroOrMore, alphanums,
                       matchPreviousExpr)


class Test(object):

    def __init__(self, s, loc, tokens):
        """Prepares a test object from the parsed tokens

        :tokens: a group of adt_test s
        """
        self.name = tokens.name
        self.output = tokens.output[0]
        self.status = tokens.status

    def __str__(self):
        return "{{Test {} {}}}".format(self.name, self.status)

hour = Regex(r'[0-9]{2}:[0-9]{2}:[0-9]{2}')

adt_msg = Literal('adt-run') + '[' + hour + ']:'
adt_msg_line = LineStart() + adt_msg

adt_testname = Word(alphanums).setResultsName('name')

adt_start = adt_msg_line + 'test' + adt_testname + ':' + '[' + OneOrMore('-')
adt_end = (
    adt_msg + 'test' + matchPreviousExpr(adt_testname) + ':' +
    OneOrMore('-') + ']'
)
adt_tail = (
    LineStart() + matchPreviousExpr(adt_testname) +
    Word(alphanums).setResultsName('status')
)

adt_test = (
    SkipTo(adt_start) + adt_start +
    SkipTo(adt_end).setResultsName('output') +
    adt_end +
    SkipTo(adt_tail) + adt_tail
).setParseAction(Test)

adt_tests = ZeroOrMore(adt_test)


def generate_test_cases(tests):
    test_cases = []
    for test in tests:
        test_case = TestCase(test.name, stdout=test.output)
        if test.status == 'PASS':
            pass
        elif test.status == 'SKIP':
            test_case.add_skipped_info(test.status)
        else:
            test_case.add_error_info(test.status)

        test_cases.append(test_case)

    return test_cases


def main():
    """ Convert the adt log output's into a junit xml file
    """
    argparser = argparse.ArgumentParser(
        description='''Convert the adt log output's into a junit xml file''')
    argparser.add_argument('input', type=open, help='Input file',
                           nargs='?', default=sys.stdin)
    argparser.add_argument('-o', '--output', type=argparse.FileType('w'),
                           help='Output file', default=sys.stdout)
    args = argparser.parse_args()

    test_cases = generate_test_cases(adt_tests.parseFile(args.input))
    test_suite = TestSuite('Autopkgtest', test_cases)
    args.output.write(TestSuite.to_xml_string([test_suite]))

if __name__ == "__main__":
    main()
