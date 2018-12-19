// CONSTANTS
// HT16K33 registers and HT16K33-specific constants
const HT16K33_BIG_SEG_CLASS_REGISTER_DISPLAY_ON  = "\x81";
const HT16K33_BIG_SEG_CLASS_REGISTER_DISPLAY_OFF = "\x80";
const HT16K33_BIG_SEG_CLASS_REGISTER_SYSTEM_ON   = "\x21";
const HT16K33_BIG_SEG_CLASS_REGISTER_SYSTEM_OFF  = "\x20";
const HT16K33_BIG_SEG_CLASS_DISPLAY_ADDRESS      = "\x00";
const HT16K33_BIG_SEG_CLASS_I2C_ADDRESS          = 0x70;
const HT16K33_BIG_SEG_CLASS_BLANK_CHAR           = 16;
const HT16K33_BIG_SEG_CLASS_MINUS_CHAR           = 17;
const HT16K33_BIG_SEG_CLASS_DEGREE_CHAR          = 18;
const HT16K33_BIG_SEG_CLASS_CHAR_COUNT           = 19;

// Display specific constants
const HT16K33_BIG_SEG_CLASS_LED_MAX_ROWS         = 4;
const HT16K33_BIG_SEG_CLASS_LED_COLON_ROW        = 2;


class HT16K33SegmentBig {
    // Hardware driver for Adafruit 1.2-inch 4-digit, 7-segment LED display
    // based on the Holtek HT16K33 controller.
    // The LED communicates over any imp I2C bus.
    // Written by Tony Smith (smittytone) 2014-18
    // Licence: MIT

    static VERSION = "1.4.0";

    // Class properties; null for those defined in the Constructor
    _buffer = null;
    _digits = null;
    _led = null;
    _ledAddress = 0;
    _debug = false;
    _logger = null;

    constructor(i2cBus = null, i2cAddress = 0x70, debug = false) {
        // Parameters:
        //   1. A CONFIGURED imp I2C bus is to be used for the HT16K33
        //   2. The HT16K33's 7-bit I2C address (default: 0x70)
        //   3. Boolean to invoke extra debug log information (default: false)

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

    function init(character = HT16K33_BIG_SEG_CLASS_BLANK_CHAR, brightness = 15, showColon = false) {
        // Parameters:
        //   1. Integer index for the digits[] character matrix to zero the display to
        //   2. Integer value for the initial display brightness, between 0 and 15
        //   3. Boolean value - should the display's colon be shown?
        // Returns:
        //   The instance

        // Initialise the display
        powerUp();
        setBrightness(brightness);
        clearBuffer(character);
        setColon(showColon ? 0x02 : 0x00);
        return this;
    }

    function setBrightness(brightness = 15) {
        // Set the LED brightness
        // Parameters:
        //   1. Integer specifying the brightness (0 - 15; default 15)
        // Returns:
        //    Nothing
        
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

    function setColon(colonPattern = 0x00) {
        // Sets the LED’s colon and decimal point lights
        // Parameter:
        //   1. An integer indicating which elements to light (OR the values required)
        //      0x00 - no colon
        //      0x02 - centre colon
        //      0x04 - left colon, lower dot
        //      0x08 - left colon, upper dot
        //      0x10 - decimal point (upper)
        // Returns:
        //   The instance

        if (typeof colonPattern != "integer") colonPatter = 0x00;
        if (colonPattern < 0 || colonPattern > 0x1E) {
            _logger.error("HT16K33SegmentBig.setColon() pattern value out of range");
        } else {
            _buffer[HT16K33_BIG_SEG_CLASS_LED_COLON_ROW] = colonPattern;
            if (_debug) _logger.log(format("Colon set to pattern 0x%02X", colonPattern));
        }

        return this;
    }

    function setDisplayFlash(flashRate = 0) {
        // Parameters:
        //    1. Flash rate in Herz. Must be 0.5, 1 or 2 for a flash, or 0 for no flash
        // Returns:
        //    Nothing

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

    function setDebug(state = true) {
        // Enable or disable extra debugging information
        // Parameters:
        //   1. Whether extra debugging information is shown. Default: true
        // Returns:
        //   Nothing

        if (typeof state != "bool") state = true;
        _debug = state;
    }

    function writeGlyph(digit, glyphPattern) {
        // Puts the character pattern into the buffer at the specified row.
        // Parameters:
        //   1. Integer specify the digit number from the left (0 - 4)
        //   2. Integer bit pattern that defines the character
        //      Bit-to-segment mapping runs clockwise from the top around the
        //      outside of the matrix; the inner segment is bit 6:
        //
        //           0
        //           _
        //       5 |   | 1
        //         |   |
        //           - <----- 6
        //       4 |   | 2
        //         | _ |
        //           3
        //
        // Returns:
        //   The instance

        if (glyphPattern < 0x00 || glyphPattern > 0x7F) {
            _logger.error("HT16K33SegmentBig.writeGlyph() glyph pattern value out of range");
            return this;
        }

        if (digit < 0 || digit > HT16K33_BIG_SEG_CLASS_LED_MAX_ROWS || digit == HT16K33_BIG_SEG_CLASS_LED_COLON_ROW) {
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

    function writeNumber(digit, number) {
        // Sets the specified digit to the number
        // Parameters:
        //   1. The digit number (0 - 4)
        //   2. The number to be displayed (0 - 15 for '0' - 'F')
        // Returns:
        //   The instance

        if (digit < 0 || digit > HT16K33_BIG_SEG_CLASS_LED_MAX_ROWS || digit == HT16K33_BIG_SEG_CLASS_LED_COLON_ROW) {
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

    function clearBuffer(character = HT16K33_BIG_SEG_CLASS_BLANK_CHAR) {
        // Fills the buffer with a specified character
        // Parameters:
        //   1. The index in the charset of the character required (0-18) 
        // Returns:
        //   The instance
        
        if (character < 0 || character > HT16K33_BIG_SEG_CLASS_CHAR_COUNT - 1) {
            character = HT16K33_BIG_SEG_CLASS_BLANK_CHAR;
            _logger.error("HT16K33SegmentBig.clearBuffer() character value out of range)");
        }

        // Put 'character' into the buffer except row 2 (colon row)
        _buffer[0] = _digits[character];
        _buffer[1] = _digits[character];
        _buffer[3] = _digits[character];
        _buffer[4] = _digits[character];

        return this;
    }

    function clearDisplay() {
        // Convenience method to clear the digits and colon, and update the display - all in one
        // Returns:
        //   Nothing
        
        clearBuffer().setColon().updateDisplay();
    }

    function updateDisplay() {
        // Converts the row-indexed buffer[] values into a single, combined
        // string and writes it to the HT16K33 via I2C
        // Returns:
        //   Nothing
        
        local dataString = HT16K33_BIG_SEG_CLASS_DISPLAY_ADDRESS;
        for (local i = 0 ; i < 5 ; i++) dataString += _buffer[i].tochar() + "\x00";
        _led.write(_ledAddress, dataString);
    }

    function powerDown() {
        // Power the LED and HT16K33 down
        // Returns:
        //   Nothing
        
        if (_debug) _logger.log("Powering HT16K33SegmentBig display down");
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS_REGISTER_DISPLAY_OFF);
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS_REGISTER_SYSTEM_OFF);
    }

    function powerUp() {
        // Power the LED and HT16K33 up
        // Returns:
        //   Nothing
        
        if (_debug) _logger.log("Powering HT16K33SegmentBig display up");
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS_REGISTER_SYSTEM_ON);
        _led.write(_ledAddress, HT16K33_BIG_SEG_CLASS_REGISTER_DISPLAY_ON);
    }
}
