module VersionHelpers
  # Converts hexadecimal representations to numbers. Does not affect Fixnums.
  #
  # returns a Fixnum
  def version_from_hex value
    value.is_a?(Fixnum) ? value : value.to_i(16)
  end
  # Converts a numeric version to an upper case hexadecimal representation.
  # Does not affect strings.
  #
  # returns a String
  def hex_from_version value
    (value.is_a?(Fixnum) ? value.to_s(16) : value.to_s).upcase
  end
  # Changes value from a hex (or Fixnum) Mac OS X gestalt version number
  # to a human readable pretty string. Ex: 0x104B and "104B" return "10.4.11"
  #
  # returns a String
  def label_from_osx_version version
    value = version_from_hex(version)
    [
      (value >> 8).to_s(16),
      (value >> 4) & 0xF,
      value & 0xF
    ].join(".")
  end
  # Parse a Mac OS X version string (such as "10.4.11") and returns the
  # numeric version of it
  #
  # returns a Fixnum
  def osx_version_from_label label
    if label =~ /([0-9]+)(?:\.([0-9]+)(?:\.([0-9]+))?)?/
      ($1.to_i(16) << 8) +
      ((($2 || 0).to_i & 0xF) << 4) +
      (($3 || 0).to_i & 0xF)
    else
      nil
    end
  end
end