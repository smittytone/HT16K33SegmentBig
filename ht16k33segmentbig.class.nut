/**
 * HT16K33 registers and HT16K33-specific variables
 * 
 * @enum
 *
 */ 
enum  HT16K33_BIG_SEG_CLASS {
        // Command registers
        REGISTER_DISPLAY_ON  = "\x81",
        REGISTER_DISPLAY_OFF = "\x80",
        REGISTER_SYSTEM_ON   = "\x21",
        REGISTER_SYSTEM_OFF  = "\x20",
        // Display hardware settings
        DISPLAY_ADDRESS      = "\x00",
        I2C_ADDRESS          = 0x70,
        // Character constants
        BLANK_CHAR           = 16,
        MINUS_CHAR           = 17,
        DEGREE_CHAR          = 18,
        CHAR_COUNT           = 19,
        // Display specific constants
        LED_MAX_ROWS         = 4,
        LED_COLON_ROW        = 2
}

/**
 * Hardware driver for Adafruit 1.2-inch 4-digit, 7-segment LED display based on the Holtek HT16K33 controller.
 * For example: http://www.adafruit.com/products/1854
 *
 * Bus          I2C
 * Availibility Device
 * @author      Tony Smith (@smittytone)
 * @license     MIT
 *
 * @class
 */
class HT16K33SegmentBig {
    
    /**
     * @property {string} VERSION - The library version
     * 
     */    
    static VERSION = "1.4.0";

    // *********** Private Properties **********

    _buffer = null;
    _digits = null;
    _led = null;
    _ledAddress = 0;
    _debug = false;
    _logger = null;

    /**
     *  Initialize the segment LED
     *
     *  @constructor
     *
     *  @param {imp::i2c} impI2Cbus    - Whichever configured imp I2C bus is to be used for the HT16K33
     *  @param {integer}  [i2cAddress] - The HT16K33's I2C address. Default: 0x70
     *  @param {bool}     [debug ]     - Set/unset to log/silence extra debug messages. Default: false
     *  
     *  @returns {instance} The instance
     */
    constructor(i2cBus = null, i2cAddress = HT16K33_BIG_SEG_CLASS.DISPLAY_ADDRESS, debug = false) {
        if (i2cBus == null || i2cAddress == 0) throw "HT16K33SegmentBig() requires a valid imp I2C object and non-zero I2C address";
        if (i2cAddress < 0x00 || i2cAddress > 0xFF) throw "HT16K33SegmentBig() requires a valid I2C address";

        _led = i2cBus;
        _ledAddress = i2cAddress << 1;
        
        if (typeof debug != "bool") debug = false;
        _debug = debug;

        // Select logging target, which stored in '_logger', and will be 'seriallog' if 'seriallog.nut'
        // has been loaded BEFORE HT16K33SegmentBig is instantiated on the device, otherwise it will be
        // the imp API object 'server'
        if ("seriallog" in getroottable()) { _logger = seriallog; } else { _logger = server; }

        // _buffer stores the character matrix values for each row of the display
        // Including the center colon character:
        //
        //     0    1   2   3    4
        //    [ ]  [ ]     [ ]  [ ]
        //     -    -   .   -    -
        //    [ ]  [ ]  .  [ ]  [ ]
        _buffer = blob(5);

        // _digits store character matrices for 0-9, A-F, blank and minus
        _digits = "\x3F\x06\x5B\x4F\x66\x6D\x7D\x07\x7F\x6F"; // 0-9
        _digits = _digits + "\x5F\x7C\x58\x5E\x7B\x71";       // A-F
        _digits = _digits + "\x00\x40\x63";                   // Space, minus, degree signs
    }

    /**
     *  Initialize the segment LED display
     *
     *  @param {integer} [character]  - A character to display on every segment. Default: clear space
     *  @param {integer} [brightness] - The LED brightness in range 0 to 15. Default: 15
     *  @param {bool}    [showColon]  - Whether the central colon should be lit. Default: false
     *
     *  @returns {intance} this  
     */
    function init(character = HT16K33_BIG_SEG_CLASS.BLANK_CHAR, brightness = 15, showColon = false) {
        // Initialise the display
        powerUp();
        setBrightness(brightness);
        clearBuffer(character);
        setColon(showColon ? 0x02 : 0x00);
        return this;
    }

    /**
     *  Set the segment LED display brightness
     *
     *  @param {integer} [brightness] - The LED brightness in range 0 to 15. Default: 15
     * 
     */
    function setBrightness(brightness = 15) {
        if (typeof brightness != "integer" && typeof brightness != "float") brightness = 15;
        brightness = brightness.tointeger();
        
        if (brightness > 15) {
            brightness = 15;
            if (_debug) _logger.log("HT16K33SegmentBig.setBrightness() brightness value out of range");
        }

        if (brightness < 0) {
            brightness = 0;
            if (_debug) _logger.log("HT16K33SegmentBig.setBrightness() brightness value out of range");
        }

        if (_debug) _logger.log("Brightness set to " + brightness);
        brightness = brightness + 224;

        // Write the new brightness value to the HT16K33
        _led.write(_ledAddress, brightness.tochar() + "\x00");
    }

    /**
     *  Set or unset the segment LED display's colon and decimal point lights
     *
     *  @param {integer} [colonPattern] - An integer indicating which elements to light (OR the values required). Default: 0x00
     *                                    0x00: no colon
     *                                    0x02: centre colon
     *                                    0x04: left colon, lower dot
     *                                    0x08: left colon, upper dot
     *                                    0x10: decimal point (upper)
     *
     *  @returns {intance} this  
     */
    function setColon(colonPattern = 0x00) {
        if (typeof colonPattern != "integer") colonPatter = 0x00;
        if (colonPattern < 0 || colonPattern > 0x1E) {
            _logger.error("HT16K33SegmentBig.setColon() pattern value out of range");
        } else {
            _buffer[HT16K33_BIG_SEG_CLASS.LED_COLON_ROW] = colonPattern;
            if (_debug) _logger.log(format("Colon set to pattern 0x%02X", colonPattern));
        }

        return this;
    }

    /**
     *  Set the segment LED to flash at one of three pre-defined rates
     *
     *  @param {integer} [flashRate] - Flash rate in Herz. Must be 0.5, 1 or 2 for a flash, or 0 for no flash. Default: 0
     * 
     */
    function setDisplayFlash(flashRate = 0) {
        local values = [0, 2, 1, 0.5];
        local match = -1;
        foreach (i, value in values) {
            if (value == flashRate) {
                match = i;
                break;
            }
        }

        if (match == -1) {
            _logger.error("HT16K33SegmentBig.setDisplayFlash() blink frequency invalid");
        } else {
            match = 0x81 + (match << 1);
            _led.write(_ledAddress, match.tochar() + "\x00");
            if (_debug) _logger.log(format("Display flash set to %d Hz", ((match - 0x81) >> 1)));
        }
    }

    /**
     *  Set the specified segment LED buffer row to a given numeric character, with a decimal point if required
     *
     *  Character matrix value is calculated by setting the bit(s) representing the segment(s) you want illuminated.
     *  Bit-to-segment mapping runs clockwise from the top around the outside of the matrix; the inner segment is bit 6:
     *
     *         0
     *         _
     *     5 |   | 1
     *       |   |
     *         - <----- 6
     *     4 |   | 2
     *       | _ |
     *         3
     * 
     *
     *  @param {integer} [digit]        - The display digit to be written to (0 - 4)
     *  @param {integer} [glyphPattern] - The integer index value of the character required
     *
     *  @returns {intance} this
     *
     */
    function writeGlyph(digit, glyphPattern) {
        if (glyphPattern < 0x00 || glyphPattern > 0x7F) {
            _logger.error("HT16K33SegmentBig.writeGlyph() glyph pattern value out of range");
            return this;
        }

        if (digit < 0 || digit > HT16K33_BIG_SEG_CLASS.LED_MAX_ROWS || digit == HT16K33_BIG_SEG_CLASS.LED_COLON_ROW) {
            _logger.error("HT16K33SegmentBig.writeGlyph() row value out of range");
            return this;
        }

        _buffer[digit] = glyphPattern;
        if (_debug) _logger.log(format("Row %d set to character defined by pattern 0x%02x", digit, glyphPattern));

        return this;
    }

    function writeChar(digit, pattern) {
        return writeGlyph(digit, pattern);
    }

    /**
     *  Set the specified segment LED buffer row to a given character
     *
     *  @param {integer} [digit]  - The display digit to be written to (0 - 4)
     *  @param {integer} [number] - The integer required (0 - 16, 0-F)
     *
     *  @returns {intance} this
     *
     */
    function writeNumber(digit, number) {
        if (digit < 0 || digit > HT16K33_BIG_SEG_CLASS.LED_MAX_ROWS || digit == HT16K33_BIG_SEG_CLASS.LED_COLON_ROW) {
            _logger.error("HT16K33SegmentBig.writeNumber() row value out of range");
            return this;
        }

        if (number < 0x00 || number > 0x0F) {
            _logger.error("HT16K33SegmentBig.writeNumber() number value out of range");
            return this;
        }

        _buffer[digit] = _digits[number];
        if (_debug) _logger.log(format("Row %d set to integer %d", digit, number));
        
        return this;
    }

    /**
     *  Set each row in the segment LED buffer to a specific character
     *
     *  @param {integer} [character] - The character to display on every segment. Default: clear space
     *
     *  @returns {intance} this
     *
     */
    function clearBuffer(character = HT16K33_BIG_SEG_CLASS.BLANK_CHAR) {
        if (character < 0 || character > HT16K33_BIG_SEG_CLASS.CHAR_COUNT - 1) {
            character = HT16K33_BIG_SEG_CLASS.BLANK_CHAR;
            _logger.error("HT16K33SegmentBig.clearBuffer() character value out of range)");
        }

        // Put 'character' into the buffer except row 2 (colon row)
        _buffer[0] = _digits[character];
        _buffer[1] = _digits[character];
        _buffer[3] = _digits[character];
        _buffer[4] = _digits[character];

        return this;
    }

    /**
     *  Set each row in the segment LED buffer to a specific character and update the display
     *
     */
    function clearDisplay() {
        clearBuffer().setColon().updateDisplay();
    }

    /**
     *  Write the segment LED buffer out to the display itself
     *
     */
    function updateDisplay() {
        local dataString = HT16K33_BIG_SEG_CLASS.DISPLAY_ADDRESS;
        for (local i = 0 ; i < 5 ; i++) dataString += _buffer[i].tochar() + "\x00";
        _led.write(_ledAddress, dataString);
    }

    /**
     *  Turn the segment LED display off
     * 
     */
    function powerDown() {
        if (_debug) _logger.log("Powering HT16K33SegmentBig display down");
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS.REGISTER_DISPLAY_OFF);
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS.REGISTER_SYSTEM_OFF);
    }

    /**
     *  Turn the segment LED display on
     * 
     */
    function powerUp() {
        if (_debug) _logger.log("Powering HT16K33SegmentBig display up");
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS.REGISTER_SYSTEM_ON);
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS.REGISTER_DISPLAY_ON);
    }

    /**
     *  Set the segment LED display to log extra debug info
     *
     *  @param {bool} [state] - Whether extra debugging is enabled (true) or not (false). Default: true
     *  
     */
    function setDebug(state = true) {
        if (typeof state != "bool") state = true;
        _debug = state;
    }
}
