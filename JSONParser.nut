/**
 * JSON Parser & Tokenizer
 *
 * @author Mikhail Yurasov <mikhail@electricimp.com>
 * @package JSONParser
 * @version 0.1.0
 */

/**
 * JSON Tokenizer
 * @package JSONParser
 */
class JSONTokenizer {

  // should be the same for all components within JSONParser package
  static version = [0, 1, 0];

  _ptfnRegex = null;
  _numberRegex = null;
  _stringRegex = null;
  _ltrimRegex = null;

  _leadingWhitespaces = 0;

  constructor() {
    // punctuation/true/false/null
    this._ptfnRegex = regexp("^(?:\\,|\\:|\\[|\\]|\\{|\\}|true|false|null)");

    // numbers
    this._numberRegex = regexp("^(?:\\-?\\d+(?:\\.\\d*)?(?:[eE][+\\-]?\\d+)?)");

    // strings
    this._stringRegex = regexp("^(?:\\\"((?:[^\\r\\n\\t\\\\\\\"]|\\\\(?:[\"\\\\\\/trnfb]|u[0-9a-fA-F]{4}))*)\\\")");

    // ltrim pattern
    this._ltrimRegex = regexp("^[\\s\\t\\n\\r]*");
  }

  /**
   * Get next available token
   * @param {string} str
   * @return {{type,value,length}|null}
   */
  function nextToken(str) {

    local
      m,
      type,
      value,
      length,
      token;

    str = this._ltrim(str);

    if (m = this._ptfnRegex.capture(str)) {
      // punctuation/true/false/null
      value = str.slice(m[0].begin, m[0].end);
      type = "ptfn";
    } else if (m = this._numberRegex.capture(str)) {
      // number
      value = str.slice(m[0].begin, m[0].end);
      type = "number";
    } else if (m = this._stringRegex.capture(str)) {
      // string
      value = str.slice(m[1].begin, m[1].end);
      type = "string";
    } else {
      return null;
    }

    token = {
      type = type,
      value = value,
      length = this._leadingWhitespaces + m[0].end
    };

    return token;
  }

  /**
   * Trim whitespace characters on the left
   * @param {string} str
   * @return {string}
   */
  function _ltrim(str) {
    local r = this._ltrimRegex.capture(str);

    if (r) {
      this._leadingWhitespaces = r[0].end;
      return str.slice(r[0].end);
    } else {
      return str;
    }
  }
}

/**
 * JSON Parser
 * @package JSONParser
 */
class JSONParser {

  // should be the same for all components within JSONParser package
  static version = [0, 1, 0];

  // enable/disable debug output
  static debug = false;

  // punctuation/true/false/null
  static ptfnPattern = "^(?:\\,|\\:|\\[|\\]|\\{|\\}|true|false|null)";

  // numbers
  static numberPattern = "^(?:\\-?\\d+(?:\\.\\d*)?(?:[eE][+\\-]?\\d+)?)";

  // strings
  static stringPattern = "^(?:\\\"((?:[^\\r\\n\\t\\\\\\\"]|\\\\(?:[\"\\\\\\/trnfb]|u[0-9a-fA-F]{4}))*)\\\")";

  // regex for trimming
  static trimPattern = regexp("^[\\s\\t\\n\\r]*");

  /**
   * Parse JSON string into data structure
   *
   * @param {string} str
   * @return {*}
   */
  function parse(str) {

    local state;
    local stack = []
    local container;
    local key;
    local value;

    // actions for string tokens
    local string = {
      go = function () {
        state = "ok";
      },
      firstokey = function () {
        key = value;
        state = "colon";
      },
      okey = function () {
        key = value;
        state = "colon";
      },
      ovalue = function () {
        state = "ocomma";
      },
      firstavalue = function () {
        state = "acomma";
      },
      avalue = function () {
        state = "acomma";
      }
    };

    // the actions for number tokens
    local number = {
      go = function () {
        state = "ok";
      },
      ovalue = function () {
        state = "ocomma";
      },
      firstavalue = function () {
        state = "acomma";
      },
      avalue = function () {
        state = "acomma";
      }
    };

    // action table
    // describes where the state machine will go from each given state
    local action = {

      "{": {
        go = function () {
          stack.push({state = "ok"});
          container = {};
          state = "firstokey";
        },
        ovalue = function () {
          stack.push({container = container, state = "ocomma", key = key});
          container = {};
          state = "firstokey";
        },
        firstavalue = function () {
          stack.push({container = container, state = "acomma"});
          container = {};
          state = "firstokey";
        },
        avalue = function () {
          stack.push({container = container, state = "acomma"});
          container = {};
          state = "firstokey";
        }
      },

      "}" : {
        firstokey = function () {
          local pop = stack.pop();
          value = container;
          container = ("container" in pop) ? pop.container : null;
          key = ("container" in pop) ? pop.key : null;
          state = pop.state;
        },
        ocomma = function () {
          local pop = stack.pop();
          container[key] <- value;
          value = container;
          container = ("container" in pop) ? pop.container : null;
          key = ("container" in pop) ? pop.key : null;
          state = pop.state;
        }
      },

      "[" : {
        go = function () {
          stack.push({state = "ok"});
          container = [];
          state = "firstavalue";
        },
        ovalue = function () {
          stack.push({container = container, state = "ocomma", key = key});
          container = [];
          state = "firstavalue";
        },
        firstavalue = function () {
          stack.push({container = container, state = "acomma"});
          container = [];
          state = "firstavalue";
        },
        avalue = function () {
          stack.push({container = container, state = "acomma"});
          container = [];
          state = "firstavalue";
        }
      },

      "]" : {
        firstavalue = function () {
          local pop = stack.pop();
          value = container;
          container = ("container" in pop) ? pop.container : null;
          key = ("container" in pop) ? pop.key : null;
          state = pop.state;
        },
        acomma = function () {
          local pop = stack.pop();
          container.push(value);
          value = container;
          container = ("container" in pop) ? pop.container : null;
          key = ("container" in pop) ? pop.key : null;
          state = pop.state;
        }
      },

      ":" : {
        colon = function () {
          // check if the key already exists
          if (key in container) {
            throw "Duplicate key \"" + key + "\"";
          }
          state = "ovalue";
        }
      },

      "," : {
        ocomma = function () {
          container[key] <- value;
          state = "okey";
        },
        acomma = function () {
          container.push(value);
          state = "avalue";
        }
      },

      "true" : {
        go = function () {
          value = true;
          state = "ok";
        },
        ovalue = function () {
          value = true;
          state = "ocomma";
        },
        firstavalue = function () {
          value = true;
          state = "acomma";
        },
        avalue = function () {
          value = true;
          state = "acomma";
        }
      },

      "false" : {
        go = function () {
          value = false;
          state = "ok";
        },
        ovalue = function () {
          value = false;
          state = "ocomma";
        },
        firstavalue = function () {
          value = false;
          state = "acomma";
        },
        avalue = function () {
          value = false;
          state = "acomma";
        }
      },

      "null" : {
        go = function () {
          value = null;
          state = "ok";
        },
        ovalue = function () {
          value = null;
          state = "ocomma";
        },
        firstavalue = function () {
          value = null;
          state = "acomma";
        },
        avalue = function () {
          value = null;
          state = "acomma";
        }
      }
    };

    //

    state = "go";
    stack = [];

    try {

      local
        result,
        token,
        tokenizer = JSONTokenizer();

      while (true) {

        token = tokenizer.nextToken(str);

        if (!token) break;

        if ("ptfn" == token.type) {
          // punctuation/true/false/null
          action[token.value][state]();
        } else if ("number" == token.type) {
          // number
          value = token.value.tofloat();
          number[state]();
        } else if ("string" == token.type) {
          // string
          value = token.value;
          string[state]();
        } else {
          break;
        }

        str = str.slice(token.length);
      }

    } catch (e) {
      throw e;
    }

    // check is the final state is not ok
    // or if there is somethign left
    if (state != "ok" || regexp("[^\\s]").match(str)) {
      throw "JSON syntax error near " + str.slice(0, str.len() > 10 ? 10 : str.len());
    }

    return value;
  }
}
