# frozen_string_literal: true

module ORB
  module Patterns
    SPACE_CHARS                   = /\s/
    TAG_NAME                      = %r{[^\s>/=$]+}
    ATTRIBUTE_NAME                = %r{[^\s>/=]+}
    UNQUOTED_VALUE_INVALID_CHARS  = /["'=<`]/
    UNQUOTED_VALUE                = %r{[^\s/>]+}
    BLOCK_NAME_CHARS              = /[^\s}]+/
    START_TAG_START               = /</
    START_TAG_END                 = />/
    START_TAG_END_SELF_CLOSING    = %r{/>}
    START_TAG_END_VERBATIM        = /\$>/
    END_TAG_START                 = %r{</}
    END_TAG_END                   = />/
    END_TAG_END_VERBATIM          = /\$>/
    PUBLIC_COMMENT_START          = /<!--/
    PUBLIC_COMMENT_END            = /-->/
    PRIVATE_COMMENT_START         = /{!--/
    PRIVATE_COMMENT_END           = /--}/
    PRINTING_EXPRESSION_START     = /{{ */
    PRINTING_EXPRESSION_END       = / *}}/
    CONTROL_EXPRESSION_START      = /{% */
    CONTROL_EXPRESSION_END        = / *%}/
    BLOCK_OPEN                    = /{#/
    BLOCK_CLOSE                   = %r[{/]
    ATTRIBUTE_ASSIGN              = /=/
    SINGLE_QUOTE                  = /'/
    DOUBLE_QUOTE                  = /"/
    SPLAT_ATTRIBUTE               = %r{\*[^\s>/=]+}
    SPLAT_EXPRESSION_START        = /\*\*\{/
    BRACE_OPEN                    = /\{/
    BRACE_CLOSE                   = /\}/
    CR                            = /\r/
    NEWLINE                       = /\n/
    CRLF                          = /\r\n/
    BLANK                         = /[[:blank:]]/
    OTHER                         = /./
  end
end
