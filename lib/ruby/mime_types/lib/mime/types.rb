# vim: ft=ruby encoding=utf-8
#--
# MIME::Types
# A Ruby implementation of a MIME Types information library. Based in spirit
# on the Perl MIME::Types information library by Mark Overmeer.
# http://rubyforge.org/projects/mime-types/
#
# Licensed under the Ruby disjunctive licence with the GNU GPL or the Perl
# Artistic licence. See Licence.txt for more information.
#
# Copyright 2003 - 2009 Austin Ziegler
#++

# The namespace for MIME applications, tools, and libraries.
module MIME
  # Reflects a MIME Content-Type which is in invalid format (e.g., it isn't
  # in the form of type/subtype).
  class InvalidContentType < RuntimeError; end

  # The definition of one MIME content-type.
  #
  # == Usage
  #  require 'mime/types'
  #
  #  plaintext = MIME::Types['text/plain']
  #  print plaintext.media_type           # => 'text'
  #  print plaintext.sub_type             # => 'plain'
  #
  #  puts plaintext.extensions.join(" ")  # => 'asc txt c cc h hh cpp'
  #
  #  puts plaintext.encoding              # => 8bit
  #  puts plaintext.binary?               # => false
  #  puts plaintext.ascii?                # => true
  #  puts plaintext == 'text/plain'       # => true
  #  puts MIME::Type.simplified('x-appl/x-zip') # => 'appl/zip'
  #
  class Type
    VERSION = '1.16'

    include Comparable

    MEDIA_TYPE_RE = %r{([-\w.+]+)/([-\w.+]*)}o
    UNREG_RE      = %r{[Xx]-}o
    ENCODING_RE   = %r{(?:base64|7bit|8bit|quoted\-printable)}o
    PLATFORM_RE   = %r|#{RUBY_PLATFORM}|o

    SIGNATURES    = %w(application/pgp-keys application/pgp
                       application/pgp-signature application/pkcs10
                       application/pkcs7-mime application/pkcs7-signature
                       text/vcard)

    IANA_URL      = "http://www.iana.org/assignments/media-types/%s/%s"
    RFC_URL       = "http://rfc-editor.org/rfc/rfc%s.txt"
    DRAFT_URL     = "http://datatracker.ietf.org/public/idindex.cgi?command=id_details&filename=%s"
    LTSW_URL      = "http://www.ltsw.se/knbase/internet/%s.htp"
    CONTACT_URL   = "http://www.iana.org/assignments/contact-people.htm#%s"

    # Returns +true+ if the simplified type matches the current
    def like?(other)
      if other.respond_to?(:simplified)
        @simplified == other.simplified
      else
        @simplified == Type.simplified(other)
      end
    end

    # Compares the MIME::Type against the exact content type or the
    # simplified type (the simplified type will be used if comparing against
    # something that can be treated as a String with #to_s). In comparisons,
    # this is done against the lowercase version of the MIME::Type.
    def <=>(other)
      if other.respond_to?(:content_type)
        @content_type.downcase <=> other.content_type.downcase
      elsif other.respond_to?(:to_s)
        @simplified <=> Type.simplified(other.to_s)
      else
        @content_type.downcase <=> other.downcase
      end
    end

    # Compares the MIME::Type based on how reliable it is before doing a
    # normal <=> comparison. Used by MIME::Types#[] to sort types. The
    # comparisons involved are:
    #
    # 1. self.simplified <=> other.simplified (ensures that we
    #    don't try to compare different types)
    # 2. IANA-registered definitions > other definitions.
    # 3. Generic definitions > platform definitions.
    # 3. Complete definitions > incomplete definitions.
    # 4. Current definitions > obsolete definitions.
    # 5. Obselete with use-instead references > obsolete without.
    # 6. Obsolete use-instead definitions are compared.
    def priority_compare(other)
      pc = simplified <=> other.simplified

      if pc.zero? and registered? != other.registered?
        pc = registered? ? -1 : 1
      end

      if pc.zero? and platform? != other.platform?
        pc = platform? ? 1 : -1
      end

      if pc.zero? and complete? != other.complete?
        pc = complete? ? -1 : 1
      end

      if pc.zero? and obsolete? != other.obsolete?
        pc = obsolete? ? 1 : -1
      end

      if pc.zero? and obsolete? and (use_instead != other.use_instead)
        pc = if use_instead.nil?
               -1
             elsif other.use_instead.nil?
               1
             else
               use_instead <=> other.use_instead
             end
      end

      pc
    end

    # Returns +true+ if the other object is a MIME::Type and the content
    # types match.
    def eql?(other)
      other.kind_of?(MIME::Type) and self == other
    end

    # Returns the whole MIME content-type string.
    #
    #   text/plain        => text/plain
    #   x-chemical/x-pdb  => x-chemical/x-pdb
    attr_reader :content_type
    # Returns the media type of the simplified MIME type.
    #
    #   text/plain        => text
    #   x-chemical/x-pdb  => chemical
    attr_reader :media_type
    # Returns the media type of the unmodified MIME type.
    #
    #   text/plain        => text
    #   x-chemical/x-pdb  => x-chemical
    attr_reader :raw_media_type
    # Returns the sub-type of the simplified MIME type.
    #
    #   text/plain        => plain
    #   x-chemical/x-pdb  => pdb
    attr_reader :sub_type
    # Returns the media type of the unmodified MIME type.
    #
    #   text/plain        => plain
    #   x-chemical/x-pdb  => x-pdb
    attr_reader :raw_sub_type
    # The MIME types main- and sub-label can both start with <tt>x-</tt>,
    # which indicates that it is a non-registered name. Of course, after
    # registration this flag can disappear, adds to the confusing
    # proliferation of MIME types. The simplified string has the <tt>x-</tt>
    # removed and are translated to lowercase.
    #
    #   text/plain        => text/plain
    #   x-chemical/x-pdb  => chemical/pdb
    attr_reader :simplified
    # The list of extensions which are known to be used for this MIME::Type.
    # Non-array values will be coerced into an array with #to_a. Array
    # values will be flattened and +nil+ values removed.
    attr_accessor :extensions
    remove_method :extensions= ;
    def extensions=(ext) #:nodoc:
      @extensions = [ext].flatten.compact
    end

    # The encoding (7bit, 8bit, quoted-printable, or base64) required to
    # transport the data of this content type safely across a network, which
    # roughly corresponds to Content-Transfer-Encoding. A value of +nil+ or
    # <tt>:default</tt> will reset the #encoding to the #default_encoding
    # for the MIME::Type. Raises ArgumentError if the encoding provided is
    # invalid.
    #
    # If the encoding is not provided on construction, this will be either
    # 'quoted-printable' (for text/* media types) and 'base64' for eveything
    # else.
    attr_accessor :encoding
    remove_method :encoding= ;
    def encoding=(enc) #:nodoc:
      if enc.nil? or enc == :default
        @encoding = self.default_encoding
      elsif enc =~ ENCODING_RE
        @encoding = enc
      else
        raise ArgumentError, "The encoding must be nil, :default, base64, 7bit, 8bit, or quoted-printable."
      end
    end

    # The regexp for the operating system that this MIME::Type is specific
    # to.
    attr_accessor :system
    remove_method :system= ;
    def system=(os) #:nodoc:
      if os.nil? or os.kind_of?(Regexp)
        @system = os
      else
        @system = %r|#{os}|
      end
    end
    # Returns the default encoding for the MIME::Type based on the media
    # type.
    attr_reader :default_encoding
    remove_method :default_encoding
    def default_encoding
      (@media_type == 'text') ? 'quoted-printable' : 'base64'
    end

    # Returns the media type or types that should be used instead of this
    # media type, if it is obsolete. If there is no replacement media type,
    # or it is not obsolete, +nil+ will be returned.
    attr_reader :use_instead
    remove_method :use_instead
    def use_instead
      return nil unless @obsolete
      @use_instead
    end

    # Returns +true+ if the media type is obsolete.
    def obsolete?
      @obsolete ? true : false
    end
    # Sets the obsolescence indicator for this media type.
    attr_writer :obsolete

    # The documentation for this MIME::Type. Documentation about media
    # types will be found on a media type definition as a comment.
    # Documentation will be found through #docs.
    attr_accessor :docs
    remove_method :docs= ;
    def docs=(d)
      if d
        a = d.scan(%r{use-instead:#{MEDIA_TYPE_RE}})

        if a.empty?
          @use_instead = nil
        else
          @use_instead = a.map { |el| "#{el[0]}/#{el[1]}" }
        end
      end
      @docs = d
    end

    # The encoded URL list for this MIME::Type. See #urls for more
    # information.
    attr_accessor :url
    # The decoded URL list for this MIME::Type.
    # The special URL value IANA will be translated into:
    #   http://www.iana.org/assignments/media-types/<mediatype>/<subtype>
    #
    # The special URL value RFC### will be translated into:
    #   http://www.rfc-editor.org/rfc/rfc###.txt
    #
    # The special URL value DRAFT:name will be translated into:
    #   https://datatracker.ietf.org/public/idindex.cgi?
    #       command=id_detail&filename=<name>
    #
    # The special URL value LTSW will be translated into:
    #   http://www.ltsw.se/knbase/internet/<mediatype>.htp
    #
    # The special URL value [token] will be translated into:
    #   http://www.iana.org/assignments/contact-people.htm#<token>
    #
    # These values will be accessible through #urls, which always returns an
    # array.
    def urls
      @url.map do |el|
        case el
        when %r{^IANA$}
          IANA_URL % [ @media_type, @sub_type ]
        when %r{^RFC(\d+)$}
          RFC_URL % $1
        when %r{^DRAFT:(.+)$}
          DRAFT_URL % $1
        when %r{^LTSW$}
          LTSW_URL % @media_type
        when %r<^\{([^=]+)=([^\]]+)\}>
          [$1, $2]
        when %r{^\[([^=]+)=([^\]]+)\]}
          [$1, CONTACT_URL % $2]
        when %r{^\[([^\]]+)\]}
          CONTACT_URL % $1
        else
          el
        end
      end
    end

    class << self
      # The MIME types main- and sub-label can both start with <tt>x-</tt>,
      # which indicates that it is a non-registered name. Of course, after
      # registration this flag can disappear, adds to the confusing
      # proliferation of MIME types. The simplified string has the
      # <tt>x-</tt> removed and are translated to lowercase.
      def simplified(content_type)
        matchdata = MEDIA_TYPE_RE.match(content_type)

        if matchdata.nil?
          simplified = nil
        else
          media_type = matchdata.captures[0].downcase.gsub(UNREG_RE, '')
          subtype = matchdata.captures[1].downcase.gsub(UNREG_RE, '')
          simplified = "#{media_type}/#{subtype}"
        end
        simplified
      end

      # Creates a MIME::Type from an array in the form of:
      #   [type-name, [extensions], encoding, system]
      #
      # +extensions+, +encoding+, and +system+ are optional.
      #
      #   MIME::Type.from_array("application/x-ruby", ['rb'], '8bit')
      #   MIME::Type.from_array(["application/x-ruby", ['rb'], '8bit'])
      #
      # These are equivalent to:
      #
      #   MIME::Type.new('application/x-ruby') do |t|
      #     t.extensions  = %w(rb)
      #     t.encoding    = '8bit'
      #   end
      def from_array(*args) #:yields MIME::Type.new:
        # Dereferences the array one level, if necessary.
        args = args[0] if args[0].kind_of?(Array)

        if args.size.between?(1, 8)
          m = MIME::Type.new(args[0]) do |t|
            t.extensions  = args[1] if args.size > 1
            t.encoding    = args[2] if args.size > 2
            t.system      = args[3] if args.size > 3
            t.obsolete    = args[4] if args.size > 4
            t.docs        = args[5] if args.size > 5
            t.url         = args[6] if args.size > 6
            t.registered  = args[7] if args.size > 7
          end
          yield m if block_given?
        else
          raise ArgumentError, "Array provided must contain between one and eight elements."
        end
        m
      end

      # Creates a MIME::Type from a hash. Keys are case-insensitive,
      # dashes may be replaced with underscores, and the internal Symbol
      # of the lowercase-underscore version can be used as well. That is,
      # Content-Type can be provided as content-type, Content_Type,
      # content_type, or :content_type.
      #
      # Known keys are <tt>Content-Type</tt>,
      # <tt>Content-Transfer-Encoding</tt>, <tt>Extensions</tt>, and
      # <tt>System</tt>.
      #
      #   MIME::Type.from_hash('Content-Type' => 'text/x-yaml',
      #                        'Content-Transfer-Encoding' => '8bit',
      #                        'System' => 'linux',
      #                        'Extensions' => ['yaml', 'yml'])
      #
      # This is equivalent to:
      #
      #   MIME::Type.new('text/x-yaml') do |t|
      #     t.encoding    = '8bit'
      #     t.system      = 'linux'
      #     t.extensions  = ['yaml', 'yml']
      #   end
      def from_hash(hash) #:yields MIME::Type.new:
        type = {}
        hash.each_pair do |k, v|
          type[k.to_s.tr('A-Z', 'a-z').gsub(/-/, '_').to_sym] = v
        end

        m = MIME::Type.new(type[:content_type]) do |t|
          t.extensions  = type[:extensions]
          t.encoding    = type[:content_transfer_encoding]
          t.system      = type[:system]
          t.obsolete    = type[:obsolete]
          t.docs        = type[:docs]
          t.url         = type[:url]
          t.registered  = type[:registered]
        end

        yield m if block_given?
        m
      end

      # Essentially a copy constructor.
      #
      #   MIME::Type.from_mime_type(plaintext)
      #
      # is equivalent to:
      #
      #   MIME::Type.new(plaintext.content_type.dup) do |t|
      #     t.extensions  = plaintext.extensions.dup
      #     t.system      = plaintext.system.dup
      #     t.encoding    = plaintext.encoding.dup
      #   end
      def from_mime_type(mime_type) #:yields the new MIME::Type:
        m = MIME::Type.new(mime_type.content_type.dup) do |t|
          t.extensions = mime_type.extensions.map { |e| e.dup }
          t.url = mime_type.url && mime_type.url.map { |e| e.dup }

          mime_type.system && t.system = mime_type.system.dup
          mime_type.encoding && t.encoding = mime_type.encoding.dup

          t.obsolete = mime_type.obsolete?
          t.registered = mime_type.registered?

          mime_type.docs && t.docs = mime_type.docs.dup

        end

        yield m if block_given?
      end
    end

    # Builds a MIME::Type object from the provided MIME Content Type value
    # (e.g., 'text/plain' or 'applicaton/x-eruby'). The constructed object
    # is yielded to an optional block for additional configuration, such as
    # associating extensions and encoding information.
    def initialize(content_type) #:yields self:
      matchdata = MEDIA_TYPE_RE.match(content_type)

      if matchdata.nil?
        raise InvalidContentType, "Invalid Content-Type provided ('#{content_type}')"
      end

      @content_type = content_type
      @raw_media_type = matchdata.captures[0]
      @raw_sub_type = matchdata.captures[1]

      @simplified = MIME::Type.simplified(@content_type)
      matchdata = MEDIA_TYPE_RE.match(@simplified)
      @media_type = matchdata.captures[0]
      @sub_type = matchdata.captures[1]

      self.extensions   = nil
      self.encoding     = :default
      self.system       = nil
      self.registered   = true
      self.url          = nil
      self.obsolete     = nil
      self.docs         = nil

      yield self if block_given?
    end

    # MIME content-types which are not regestered by IANA nor defined in
    # RFCs are required to start with <tt>x-</tt>. This counts as well for
    # a new media type as well as a new sub-type of an existing media
    # type. If either the media-type or the content-type begins with
    # <tt>x-</tt>, this method will return +false+.
    def registered?
      if (@raw_media_type =~ UNREG_RE) || (@raw_sub_type =~ UNREG_RE)
        false
      else
        @registered
      end
    end
    attr_writer :registered #:nodoc:

    # MIME types can be specified to be sent across a network in particular
    # formats. This method returns +true+ when the MIME type encoding is set
    # to <tt>base64</tt>.
    def binary?
      @encoding == 'base64'
    end

    # MIME types can be specified to be sent across a network in particular
    # formats. This method returns +false+ when the MIME type encoding is
    # set to <tt>base64</tt>.
    def ascii?
      not binary?
    end

    # Returns +true+ when the simplified MIME type is in the list of known
    # digital signatures.
    def signature?
      SIGNATURES.include?(@simplified.downcase)
    end

    # Returns +true+ if the MIME::Type is specific to an operating system.
    def system?
      not @system.nil?
    end

    # Returns +true+ if the MIME::Type is specific to the current operating
    # system as represented by RUBY_PLATFORM.
    def platform?
      system? and (RUBY_PLATFORM =~ @system)
    end

    # Returns +true+ if the MIME::Type specifies an extension list,
    # indicating that it is a complete MIME::Type.
    def complete?
      not @extensions.empty?
    end

    # Returns the MIME type as a string.
    def to_s
      @content_type
    end

    # Returns the MIME type as a string for implicit conversions.
    def to_str
      @content_type
    end

    # Returns the MIME type as an array suitable for use with
    # MIME::Type.from_array.
    def to_a
      [ @content_type, @extensions, @encoding, @system, @obsolete, @docs,
        @url, registered? ]
    end

    # Returns the MIME type as an array suitable for use with
    # MIME::Type.from_hash.
    def to_hash
      { 'Content-Type'              => @content_type,
        'Content-Transfer-Encoding' => @encoding,
        'Extensions'                => @extensions,
        'System'                    => @system,
        'Obsolete'                  => @obsolete,
        'Docs'                      => @docs,
        'URL'                       => @url,
        'Registered'                => registered?,
      }
    end
  end

  # = MIME::Types
  # MIME types are used in MIME-compliant communications, as in e-mail or
  # HTTP traffic, to indicate the type of content which is transmitted.
  # MIME::Types provides the ability for detailed information about MIME
  # entities (provided as a set of MIME::Type objects) to be determined and
  # used programmatically. There are many types defined by RFCs and vendors,
  # so the list is long but not complete; don't hesitate to ask to add
  # additional information. This library follows the IANA collection of MIME
  # types (see below for reference).
  #
  # == Description
  # MIME types are used in MIME entities, as in email or HTTP traffic. It is
  # useful at times to have information available about MIME types (or,
  # inversely, about files). A MIME::Type stores the known information about
  # one MIME type.
  #
  # == Usage
  #  require 'mime/types'
  #
  #  plaintext = MIME::Types['text/plain']
  #  print plaintext.media_type           # => 'text'
  #  print plaintext.sub_type             # => 'plain'
  #
  #  puts plaintext.extensions.join(" ")  # => 'asc txt c cc h hh cpp'
  #
  #  puts plaintext.encoding              # => 8bit
  #  puts plaintext.binary?               # => false
  #  puts plaintext.ascii?                # => true
  #  puts plaintext.obsolete?             # => false
  #  puts plaintext.registered?           # => true
  #  puts plaintext == 'text/plain'       # => true
  #  puts MIME::Type.simplified('x-appl/x-zip') # => 'appl/zip'
  #
  # This module is built to conform to the MIME types of RFCs 2045 and 2231.
  # It follows the official IANA registry at
  # http://www.iana.org/assignments/media-types/ and
  # ftp://ftp.iana.org/assignments/media-types with some unofficial types
  # added from the the collection at
  # http://www.ltsw.se/knbase/internet/mime.htp
  #
  # This is originally based on Perl MIME::Types by Mark Overmeer.
  #
  # = Author
  # Copyright:: Copyright (c) 2002 - 2009 by Austin Ziegler
  #             <austin@rubyforge.org>
  # Version::   1.16
  # Based On::  Perl
  #             MIME::Types[http://search.cpan.org/author/MARKOV/MIME-Types-1.27/MIME/Types.pm],
  #             Copyright (c) 2001 - 2009 by Mark Overmeer
  #             <mimetypes@overmeer.net>.
  # Licence::   Ruby's, Perl Artistic, or GPL version 2 (or later)
  # See Also::  http://www.iana.org/assignments/media-types/
  #             http://www.ltsw.se/knbase/internet/mime.htp
  #
  class Types
    # The released version of Ruby MIME::Types
    VERSION  = '1.16'

      # The data version.
    attr_reader :data_version

    def initialize(data_version = nil)
      @type_variants    = Hash.new { |h, k| h[k] = [] }
      @extension_index  = Hash.new { |h, k| h[k] = [] }
    end

    def add_type_variant(mime_type) #:nodoc:
      @type_variants[mime_type.simplified] << mime_type
    end

    def index_extensions(mime_type) #:nodoc:
      mime_type.extensions.each { |ext| @extension_index[ext] << mime_type }
    end

    @__types__ = self.new(VERSION)

    # Returns a list of MIME::Type objects, which may be empty. The optional
    # flag parameters are :complete (finds only complete MIME::Type objects)
    # and :platform (finds only MIME::Types for the current platform). It is
    # possible for multiple matches to be returned for either type (in the
    # example below, 'text/plain' returns two values -- one for the general
    # case, and one for VMS systems.
    #
    #   puts "\nMIME::Types['text/plain']"
    #   MIME::Types['text/plain'].each { |t| puts t.to_a.join(", ") }
    #
    #   puts "\nMIME::Types[/^image/, :complete => true]"
    #   MIME::Types[/^image/, :complete => true].each do |t|
    #     puts t.to_a.join(", ")
    #   end
    #
    # If multiple type definitions are returned, returns them sorted as
    # follows:
    #   1. Complete definitions sort before incomplete ones;
    #   2. IANA-registered definitions sort before LTSW-recorded
    #      definitions.
    #   3. Generic definitions sort before platform-specific ones;
    #   4. Current definitions sort before obsolete ones;
    #   5. Obsolete definitions with use-instead clauses sort before those
    #      without;
    #   6. Obsolete definitions use-instead clauses are compared.
    #   7. Sort on name.
    def [](type_id, flags = {})
      if type_id.kind_of?(Regexp)
        matches = []
        @type_variants.each_key do |k|
          matches << @type_variants[k] if k =~ type_id
        end
        matches.flatten!
      elsif type_id.kind_of?(MIME::Type)
        matches = [type_id]
      else
        matches = @type_variants[MIME::Type.simplified(type_id)]
      end

      matches.delete_if { |e| not e.complete? } if flags[:complete]
      matches.delete_if { |e| not e.platform? } if flags[:platform]

      matches.sort { |a, b| a.priority_compare(b) }
    end

    # Return the list of MIME::Types which belongs to the file based on its
    # filename extension. If +platform+ is +true+, then only file types that
    # are specific to the current platform will be returned.
    #
    #   puts "MIME::Types.type_for('citydesk.xml')
    #     => "#{MIME::Types.type_for('citydesk.xml')}"
    #   puts "MIME::Types.type_for('citydesk.gif')
    #     => "#{MIME::Types.type_for('citydesk.gif')}"
    def type_for(filename, platform = false)
      ext = filename.chomp.downcase.gsub(/.*\./o, '')
      list = @extension_index[ext]
      list.delete_if { |e| not e.platform? } if platform
      list
    end

    # A synonym for MIME::Types.type_for
    def of(filename, platform = false)
      type_for(filename, platform)
    end

    # Add one or more MIME::Type objects to the set of known types. Each
    # type should be experimental (e.g., 'application/x-ruby'). If the type
    # is already known, a warning will be displayed.
    #
    # <b>Please inform the maintainer of this module when registered types
    # are missing.</b>
    def add(*types)
      types.each do |mime_type|
        if @type_variants.include?(mime_type.simplified)
          if @type_variants[mime_type.simplified].include?(mime_type)
            warn "Type #{mime_type} already registered as a variant of #{mime_type.simplified}."
          end
        end
        add_type_variant(mime_type)
        index_extensions(mime_type)
      end
    end

    class << self
      def add_type_variant(mime_type) #:nodoc:
        @__types__.add_type_variant(mime_type)
      end

      def index_extensions(mime_type) #:nodoc:
        @__types__.index_extensions(mime_type)
      end

      # Returns a list of MIME::Type objects, which may be empty. The
      # optional flag parameters are :complete (finds only complete
      # MIME::Type objects) and :platform (finds only MIME::Types for the
      # current platform). It is possible for multiple matches to be
      # returned for either type (in the example below, 'text/plain' returns
      # two values -- one for the general case, and one for VMS systems.
      #
      #   puts "\nMIME::Types['text/plain']"
      #   MIME::Types['text/plain'].each { |t| puts t.to_a.join(", ") }
      #
      #   puts "\nMIME::Types[/^image/, :complete => true]"
      #   MIME::Types[/^image/, :complete => true].each do |t|
      #     puts t.to_a.join(", ")
      #   end
      def [](type_id, flags = {})
        @__types__[type_id, flags]
      end

      # Return the list of MIME::Types which belongs to the file based on
      # its filename extension. If +platform+ is +true+, then only file
      # types that are specific to the current platform will be returned.
      #
      #   puts "MIME::Types.type_for('citydesk.xml')
      #     => "#{MIME::Types.type_for('citydesk.xml')}"
      #   puts "MIME::Types.type_for('citydesk.gif')
      #     => "#{MIME::Types.type_for('citydesk.gif')}"
      def type_for(filename, platform = false)
        @__types__.type_for(filename, platform)
      end

      # A synonym for MIME::Types.type_for
      def of(filename, platform = false)
        @__types__.type_for(filename, platform)
      end

      # Add one or more MIME::Type objects to the set of known types. Each
      # type should be experimental (e.g., 'application/x-ruby'). If the
      # type is already known, a warning will be displayed.
      #
      # <b>Please inform the maintainer of this module when registered types
      # are missing.</b>
      def add(*types)
        @__types__.add(*types)
      end
    end
  end
end

# vim: ft=ruby encoding=utf-8
#--
# MIME::Types
# A Ruby implementation of a MIME Types information library. Based in spirit
# on the Perl MIME::Types information library by Mark Overmeer.
# http://rubyforge.org/projects/mime-types/
#
# Licensed under the Ruby disjunctive licence with the GNU GPL or the Perl
# Artistic licence. See Licence.txt for more information.
#
# Copyright 2003 - 2009 Austin Ziegler
#++

# Build the type list from the string below.
#
#   [*][!][os:]mt/st[<ws>@ext][<ws>:enc][<ws>'url-list][<ws>=docs]
#
# == *
# An unofficial MIME type. This should be used if and only if the MIME type
# is not properly specified (that is, not under either x-type or
# vnd.name.type).
#
# == !
# An obsolete MIME type. May be used with an unofficial MIME type.
#
# == os:
# Platform-specific MIME type definition.
#
# == mt
# The media type.
#
# == st
# The media subtype.
#
# == <ws>@ext
# The list of comma-separated extensions.
#
# == <ws>:enc
# The encoding.
#
# == <ws>'url-list
# The list of comma-separated URLs.
#
# == <ws>=docs
# The documentation string.
#
# That is, everything except the media type and the subtype is optional. The
# more information that's available, though, the richer the values that can
# be provided.

data_mime_type_first_line = __LINE__ + 2
data_mime_type = <<MIME_TYPES
  # application/*
application/activemessage 'IANA,[Shapiro]
application/andrew-inset 'IANA,[Borenstein]
application/applefile :base64 'IANA,[Faltstrom]
application/atom+xml @atom :8bit 'IANA,RFC4287,RFC5023
application/atomcat+xml :8bit 'IANA,RFC5023
application/atomicmail 'IANA,[Borenstein]
application/atomsvc+xml :8bit 'IANA,RFC5023
application/auth-policy+xml :8bit 'IANA,RFC4745
application/batch-SMTP 'IANA,RFC2442
application/beep+xml 'IANA,RFC3080
application/cals-1840 'IANA,RFC1895
application/ccxml+xml 'IANA,RFC4267
application/cea-2018+xml 'IANA,[Zimmermann]
application/cellml+xml 'IANA,RFC4708
application/cnrp+xml 'IANA,RFC3367
application/commonground 'IANA,[Glazer]
application/conference-info+xml 'IANA,RFC4575
application/cpl+xml 'IANA,RFC3880
application/csta+xml 'IANA,[Ecma International Helpdesk]
application/CSTAdata+xml 'IANA,[Ecma International Helpdesk]
application/cybercash 'IANA,[Eastlake]
application/davmount+xml 'IANA,RFC4709
application/dca-rft 'IANA,[Campbell]
application/dec-dx 'IANA,[Campbell]
application/dialog-info+xml 'IANA,RFC4235
application/dicom 'IANA,RFC3240
application/dns 'IANA,RFC4027
application/dvcs 'IANA,RFC3029
application/ecmascript 'IANA,RFC4329
application/EDI-Consent 'IANA,RFC1767
application/EDI-X12 'IANA,RFC1767
application/EDIFACT 'IANA,RFC1767
application/emma+xml 'IANA,[W3C]
application/epp+xml 'IANA,RFC3730
application/eshop 'IANA,[Katz]
application/fastinfoset 'IANA,[ITU-T ASN.1 Rapporteur]
application/fastsoap 'IANA,[ITU-T ASN.1 Rapporteur]
application/fits 'IANA,RFC4047
application/font-tdpfr @pfr 'IANA,RFC3073
application/H224 'IANA,RFC4573
application/http 'IANA,RFC2616
application/hyperstudio @stk 'IANA,[Domino]
application/ibe-key-request+xml 'IANA,RFC5408
application/ibe-pkg-reply+xml 'IANA,RFC5408
application/ibe-pp-data 'IANA,RFC5408
application/iges 'IANA,[Parks]
application/im-iscomposing+xml 'IANA,RFC3994
application/index 'IANA,RFC2652
application/index.cmd 'IANA,RFC2652
application/index.obj 'IANA,RFC2652
application/index.response 'IANA,RFC2652
application/index.vnd 'IANA,RFC2652
application/iotp 'IANA,RFC2935
application/ipp 'IANA,RFC2910
application/isup 'IANA,RFC3204
application/javascript @js :8bit 'IANA,RFC4329
application/json @json :8bit 'IANA,RFC4627
application/kpml-request+xml 'IANA,RFC4730
application/kpml-response+xml 'IANA,RFC4730
application/lost+xml 'IANA,RFC5222
application/mac-binhex40 @hqx :8bit 'IANA,[Faltstrom]
application/macwriteii 'IANA,[Lindner]
application/marc 'IANA,RFC2220
application/mathematica 'IANA,[Wolfram]
application/mbms-associated-procedure-description+xml 'IANA,[3GPP]
application/mbms-deregister+xml 'IANA,[3GPP]
application/mbms-envelope+xml 'IANA,[3GPP]
application/mbms-msk+xml 'IANA,[3GPP]
application/mbms-msk-response+xml 'IANA,[3GPP]
application/mbms-protection-description+xml 'IANA,[3GPP]
application/mbms-reception-report+xml 'IANA,[3GPP]
application/mbms-register+xml 'IANA,[3GPP]
application/mbms-register-response+xml 'IANA,[3GPP]
application/mbms-user-service-description+xml 'IANA,[3GPP]
application/mbox 'IANA,RFC4155
application/media_control+xml 'IANA,RFC5168
application/mediaservercontrol+xml 'IANA,RFC5022
application/mikey 'IANA,RFC3830
application/moss-keys 'IANA,RFC1848
application/moss-signature 'IANA,RFC1848
application/mosskey-data 'IANA,RFC1848
application/mosskey-request 'IANA,RFC1848
application/mp4 'IANA,RFC4337
application/mpeg4-generic 'IANA,RFC3640
application/mpeg4-iod 'IANA,RFC4337
application/mpeg4-iod-xmt 'IANA,RFC4337
application/msword @doc,dot,wrd :base64 'IANA,[Lindner]
application/mxf 'IANA,RFC4539
application/nasdata 'IANA,RFC4707
application/news-transmission 'IANA,RFC1036,[Spencer]
application/nss 'IANA,[Hammer]
application/ocsp-request 'IANA,RFC2560
application/ocsp-response 'IANA,RFC2560
application/octet-stream @bin,dms,lha,lzh,exe,class,ani,pgp,so,dll,dmg,dylib :base64 'IANA,RFC2045,RFC2046
application/oda @oda 'IANA,RFC2045,RFC2046
application/oebps-package+xml 'IANA,RFC4839
application/ogg @ogx 'IANA,RFC5334
application/parityfec 'IANA,RFC5109
application/patch-ops-error+xml 'IANA,RFC5261
application/pdf @pdf :base64 'IANA,RFC3778
application/pgp-encrypted :7bit 'IANA,RFC3156
application/pgp-keys :7bit 'IANA,RFC3156
application/pgp-signature @sig :base64 'IANA,RFC3156
application/pidf+xml 'IANA,RFC3863
application/pidf-diff+xml 'IANA,RFC5262
application/pkcs10 @p10 'IANA,RFC2311
application/pkcs7-mime @p7m,p7c 'IANA,RFC2311
application/pkcs7-signature @p7s 'IANA,RFC2311
application/pkix-cert @cer 'IANA,RFC2585
application/pkix-crl @crl 'IANA,RFC2585
application/pkix-pkipath @pkipath 'IANA,RFC4366
application/pkixcmp @pki 'IANA,RFC2510
application/pls+xml 'IANA,RFC4267
application/poc-settings+xml 'IANA,RFC4354
application/postscript @ai,eps,ps :8bit 'IANA,RFC2045,RFC2046
application/prs.alvestrand.titrax-sheet 'IANA,[Alvestrand]
application/prs.cww @cw,cww 'IANA,[Rungchavalnont]
application/prs.nprend @rnd,rct 'IANA,[Doggett]
application/prs.plucker 'IANA,[Janssen]
application/qsig 'IANA,RFC3204
application/rdf+xml @rdf :8bit 'IANA,RFC3870
application/reginfo+xml 'IANA,RFC3680
application/relax-ng-compact-syntax 'IANA,{ISO/IEC 1957-2:2003/FDAM-1=http://www.jtc1sc34.org/repository/0661.pdf}
application/remote-printing 'IANA,RFC1486,[Rose]
application/resource-lists+xml 'IANA,RFC4826
application/resource-lists-diff+xml 'IANA,RFC5362
application/riscos 'IANA,[Smith]
application/rlmi+xml 'IANA,RFC4662
application/rls-services+xml 'IANA,RFC4826
application/rtf @rtf 'IANA,[Lindner]
application/rtx 'IANA,RFC4588
application/samlassertion+xml 'IANA,[OASIS Security Services Technical Committee (SSTC)]
application/samlmetadata+xml 'IANA,[OASIS Security Services Technical Committee (SSTC)]
application/sbml+xml 'IANA,RFC3823
application/scvp-cv-request 'IANA,RFC5055
application/scvp-cv-response 'IANA,RFC5055
application/scvp-vp-request 'IANA,RFC5055
application/scvp-vp-response 'IANA,RFC5055
application/sdp 'IANA,RFC4566
application/set-payment 'IANA,[Korver]
application/set-payment-initiation 'IANA,[Korver]
application/set-registration 'IANA,[Korver]
application/set-registration-initiation 'IANA,[Korver]
application/sgml @sgml 'IANA,RFC1874
application/sgml-open-catalog @soc 'IANA,[Grosso]
application/shf+xml 'IANA,RFC4194
application/sieve @siv 'IANA,RFC5228
application/simple-filter+xml 'IANA,RFC4661
application/simple-message-summary 'IANA,RFC3842
application/simpleSymbolContainer 'IANA,[3GPP]
application/slate 'IANA,[Crowley]
application/smil+xml @smi,smil :8bit 'IANA,RFC4536
application/soap+fastinfoset 'IANA,[ITU-T ASN.1 Rapporteur]
application/soap+xml 'IANA,RFC3902
application/sparql-query 'IANA,[W3C]
application/sparql-results+xml 'IANA,[W3C]
application/spirits-event+xml 'IANA,RFC3910
application/srgs 'IANA,RFC4267
application/srgs+xml 'IANA,RFC4267
application/ssml+xml 'IANA,RFC4267
application/timestamp-query 'IANA,RFC3161
application/timestamp-reply 'IANA,RFC3161
application/tve-trigger 'IANA,[Welsh]
application/ulpfec 'IANA,RFC5109
application/vemmi 'IANA,RFC2122
application/vnd.3gpp.bsf+xml 'IANA,[Meredith]
application/vnd.3gpp.pic-bw-large @plb 'IANA,[Meredith]
application/vnd.3gpp.pic-bw-small @psb 'IANA,[Meredith]
application/vnd.3gpp.pic-bw-var @pvb 'IANA,[Meredith]
application/vnd.3gpp.sms @sms 'IANA,[Meredith]
application/vnd.3gpp2.bcmcsinfo+xml 'IANA,[Dryden]
application/vnd.3gpp2.sms 'IANA,[Mahendran]
application/vnd.3gpp2.tcap 'IANA,[Mahendran]
application/vnd.3M.Post-it-Notes 'IANA,[O'Brien]
application/vnd.accpac.simply.aso 'IANA,[Leow]
application/vnd.accpac.simply.imp 'IANA,[Leow]
application/vnd.acucobol 'IANA,[Lubin]
application/vnd.acucorp @atc,acutc :7bit 'IANA,[Lubin]
application/vnd.adobe.xdp+xml 'IANA,[Brinkman]
application/vnd.adobe.xfdf @xfdf 'IANA,[Perelman]
application/vnd.aether.imp 'IANA,[Moskowitz]
application/vnd.airzip.filesecure.azf 'IANA,[Mould],[Clueit]
application/vnd.airzip.filesecure.azs 'IANA,[Mould],[Clueit]
application/vnd.americandynamics.acc 'IANA,[Sands]
application/vnd.amiga.ami @ami 'IANA,[Blumberg]
application/vnd.anser-web-certificate-issue-initiation 'IANA,[Mori]
application/vnd.antix.game-component 'IANA,[Shelton]
application/vnd.apple.installer+xml 'IANA,[Bierman]
application/vnd.arastra.swi 'IANA,[Fenner]
application/vnd.audiograph 'IANA,[Slusanschi]
application/vnd.autopackage 'IANA,[Hearn]
application/vnd.avistar+xml 'IANA,[Vysotsky]
application/vnd.blueice.multipass @mpm 'IANA,[Holmstrom]
application/vnd.bluetooth.ep.oob 'IANA,[Foley]
application/vnd.bmi 'IANA,[Gotoh]
application/vnd.businessobjects 'IANA,[Imoucha]
application/vnd.cab-jscript 'IANA,[Falkenberg]
application/vnd.canon-cpdl 'IANA,[Muto]
application/vnd.canon-lips 'IANA,[Muto]
application/vnd.cendio.thinlinc.clientconf 'IANA,[Åstrand=Astrand]
application/vnd.chemdraw+xml 'IANA,[Howes]
application/vnd.chipnuts.karaoke-mmd 'IANA,[Xiong]
application/vnd.cinderella @cdy 'IANA,[Kortenkamp]
application/vnd.cirpack.isdn-ext 'IANA,[Mayeux]
application/vnd.claymore 'IANA,[Simpson]
application/vnd.clonk.c4group 'IANA,[Brammer]
application/vnd.commerce-battelle 'IANA,[Applebaum]
application/vnd.commonspace 'IANA,[Chandhok]
application/vnd.contact.cmsg 'IANA,[Patz]
application/vnd.cosmocaller @cmc 'IANA,[Dellutri]
application/vnd.crick.clicker 'IANA,[Burt]
application/vnd.crick.clicker.keyboard 'IANA,[Burt]
application/vnd.crick.clicker.palette 'IANA,[Burt]
application/vnd.crick.clicker.template 'IANA,[Burt]
application/vnd.crick.clicker.wordbank 'IANA,[Burt]
application/vnd.criticaltools.wbs+xml @wbs 'IANA,[Spiller]
application/vnd.ctc-posml 'IANA,[Kohlhepp]
application/vnd.ctct.ws+xml 'IANA,[Ancona]
application/vnd.cups-pdf 'IANA,[Sweet]
application/vnd.cups-postscript 'IANA,[Sweet]
application/vnd.cups-ppd 'IANA,[Sweet]
application/vnd.cups-raster 'IANA,[Sweet]
application/vnd.cups-raw 'IANA,[Sweet]
application/vnd.curl @curl 'IANA,[Byrnes]
application/vnd.cybank 'IANA,[Helmee]
application/vnd.data-vision.rdz @rdz 'IANA,[Fields]
application/vnd.denovo.fcselayout-link 'IANA,[Dixon]
application/vnd.dir-bi.plate-dl-nosuffix 'IANA,[Yamanaka]
application/vnd.dna 'IANA,[Searcy]
application/vnd.dpgraph 'IANA,[Parker]
application/vnd.dreamfactory @dfac 'IANA,[Appleton]
application/vnd.dvb.esgcontainer 'IANA,[Heuer]
application/vnd.dvb.ipdcesgaccess 'IANA,[Heuer]
application/vnd.dvb.iptv.alfec-base 'IANA,[Henry]
application/vnd.dvb.iptv.alfec-enhancement 'IANA,[Henry]
application/vnd.dvb.notif-container+xml 'IANA,[Yue]
application/vnd.dvb.notif-generic+xml 'IANA,[Yue]
application/vnd.dvb.notif-ia-msglist+xml 'IANA,[Yue]
application/vnd.dvb.notif-ia-registration-request+xml 'IANA,[Yue]
application/vnd.dvb.notif-ia-registration-response+xml 'IANA,[Yue]
application/vnd.dxr 'IANA,[Duffy]
application/vnd.ecdis-update 'IANA,[Buettgenbach]
application/vnd.ecowin.chart 'IANA,[Olsson]
application/vnd.ecowin.filerequest 'IANA,[Olsson]
application/vnd.ecowin.fileupdate 'IANA,[Olsson]
application/vnd.ecowin.series 'IANA,[Olsson]
application/vnd.ecowin.seriesrequest 'IANA,[Olsson]
application/vnd.ecowin.seriesupdate 'IANA,[Olsson]
application/vnd.emclient.accessrequest+xml 'IANA,[Navara]
application/vnd.enliven 'IANA,[Santinelli]
application/vnd.epson.esf 'IANA,[Hoshina]
application/vnd.epson.msf 'IANA,[Hoshina]
application/vnd.epson.quickanime 'IANA,[Gu]
application/vnd.epson.salt 'IANA,[Nagatomo]
application/vnd.epson.ssf 'IANA,[Hoshina]
application/vnd.ericsson.quickcall 'IANA,[Tidwell]
application/vnd.eszigno3+xml 'IANA,[Tóth=Toth]
application/vnd.eudora.data 'IANA,[Resnick]
application/vnd.ezpix-album 'IANA,[Electronic Zombie, Corp.=ElectronicZombieCorp]
application/vnd.ezpix-package 'IANA,[Electronic Zombie, Corp.=ElectronicZombieCorp]
application/vnd.f-secure.mobile 'IANA,[Sarivaara]
application/vnd.fdf 'IANA,[Zilles]
application/vnd.fdsn.mseed 'IANA,[Ratzesberger]
application/vnd.ffsns 'IANA,[Holstage]
application/vnd.fints 'IANA,[Hammann]
application/vnd.FloGraphIt 'IANA,[Floersch]
application/vnd.fluxtime.clip 'IANA,[Winter]
application/vnd.font-fontforge-sfd 'IANA,[Williams]
application/vnd.framemaker @frm,maker,frame,fm,fb,book,fbdoc 'IANA,[Wexler]
application/vnd.frogans.fnc 'IANA,[Tamas]
application/vnd.frogans.ltf 'IANA,[Tamas]
application/vnd.fsc.weblaunch @fsc :7bit 'IANA,[D.Smith]
application/vnd.fujitsu.oasys 'IANA,[Togashi]
application/vnd.fujitsu.oasys2 'IANA,[Togashi]
application/vnd.fujitsu.oasys3 'IANA,[Okudaira]
application/vnd.fujitsu.oasysgp 'IANA,[Sugimoto]
application/vnd.fujitsu.oasysprs 'IANA,[Ogita]
application/vnd.fujixerox.ART-EX 'IANA,[Tanabe]
application/vnd.fujixerox.ART4 'IANA,[Tanabe]
application/vnd.fujixerox.ddd 'IANA,[Onda]
application/vnd.fujixerox.docuworks 'IANA,[Taguchi]
application/vnd.fujixerox.docuworks.binder 'IANA,[Matsumoto]
application/vnd.fujixerox.HBPL 'IANA,[Tanabe]
application/vnd.fut-misnet 'IANA,[Pruulmann]
application/vnd.fuzzysheet 'IANA,[Birtwistle]
application/vnd.genomatix.tuxedo @txd 'IANA,[Frey]
application/vnd.geogebra.file 'IANA,[GeoGebra],[Kreis]
application/vnd.gmx 'IANA,[Sciberras]
application/vnd.google-earth.kml+xml @kml :8bit 'IANA,[Ashbridge]
application/vnd.google-earth.kmz @kmz :8bit 'IANA,[Ashbridge]
application/vnd.grafeq 'IANA,[Tupper]
application/vnd.gridmp 'IANA,[Lawson]
application/vnd.groove-account 'IANA,[Joseph]
application/vnd.groove-help 'IANA,[Joseph]
application/vnd.groove-identity-message 'IANA,[Joseph]
application/vnd.groove-injector 'IANA,[Joseph]
application/vnd.groove-tool-message 'IANA,[Joseph]
application/vnd.groove-tool-template 'IANA,[Joseph]
application/vnd.groove-vcard 'IANA,[Joseph]
application/vnd.HandHeld-Entertainment+xml 'IANA,[Hamilton]
application/vnd.hbci @hbci,hbc,kom,upa,pkd,bpd 'IANA,[Hammann]
application/vnd.hcl-bireports 'IANA,[Serres]
application/vnd.hhe.lesson-player @les 'IANA,[Jones]
application/vnd.hp-HPGL @plt,hpgl 'IANA,[Pentecost]
application/vnd.hp-hpid 'IANA,[Gupta]
application/vnd.hp-hps 'IANA,[Aubrey]
application/vnd.hp-jlyt 'IANA,[Gaash]
application/vnd.hp-PCL 'IANA,[Pentecost]
application/vnd.hp-PCLXL 'IANA,[Pentecost]
application/vnd.httphone 'IANA,[Lefevre]
application/vnd.hydrostatix.sof-data 'IANA,[Gillam]
application/vnd.hzn-3d-crossword 'IANA,[Minnis]
application/vnd.ibm.afplinedata 'IANA,[Buis]
application/vnd.ibm.electronic-media @emm 'IANA,[Tantlinger]
application/vnd.ibm.MiniPay 'IANA,[Herzberg]
application/vnd.ibm.modcap 'IANA,[Hohensee]
application/vnd.ibm.rights-management @irm 'IANA,[Tantlinger]
application/vnd.ibm.secure-container @sc 'IANA,[Tantlinger]
application/vnd.iccprofile 'IANA,[Green]
application/vnd.igloader 'IANA,[Fisher]
application/vnd.immervision-ivp 'IANA,[Villegas]
application/vnd.immervision-ivu 'IANA,[Villegas]
application/vnd.informedcontrol.rms+xml 'IANA,[Wahl]
application/vnd.informix-visionary 'IANA,[Gales]
application/vnd.intercon.formnet 'IANA,[Gurak]
application/vnd.intertrust.digibox 'IANA,[Tomasello]
application/vnd.intertrust.nncp 'IANA,[Tomasello]
application/vnd.intu.qbo 'IANA,[Scratchley]
application/vnd.intu.qfx 'IANA,[Scratchley]
application/vnd.iptc.g2.conceptitem+xml 'IANA,[Steidl]
application/vnd.iptc.g2.knowledgeitem+xml 'IANA,[Steidl]
application/vnd.iptc.g2.newsitem+xml 'IANA,[Steidl]
application/vnd.iptc.g2.packageitem+xml 'IANA,[Steidl]
application/vnd.ipunplugged.rcprofile @rcprofile 'IANA,[Ersson]
application/vnd.irepository.package+xml @irp 'IANA,[Knowles]
application/vnd.is-xpr 'IANA,[Natarajan]
application/vnd.jam 'IANA,[B.Kumar]
application/vnd.japannet-directory-service 'IANA,[Fujii]
application/vnd.japannet-jpnstore-wakeup 'IANA,[Yoshitake]
application/vnd.japannet-payment-wakeup 'IANA,[Fujii]
application/vnd.japannet-registration 'IANA,[Yoshitake]
application/vnd.japannet-registration-wakeup 'IANA,[Fujii]
application/vnd.japannet-setstore-wakeup 'IANA,[Yoshitake]
application/vnd.japannet-verification 'IANA,[Yoshitake]
application/vnd.japannet-verification-wakeup 'IANA,[Fujii]
application/vnd.jcp.javame.midlet-rms 'IANA,[Gorshenev]
application/vnd.jisp @jisp 'IANA,[Deckers]
application/vnd.joost.joda-archive 'IANA,[Joost]
application/vnd.kahootz 'IANA,[Macdonald]
application/vnd.kde.karbon @karbon 'IANA,[Faure]
application/vnd.kde.kchart @chrt 'IANA,[Faure]
application/vnd.kde.kformula @kfo 'IANA,[Faure]
application/vnd.kde.kivio @flw 'IANA,[Faure]
application/vnd.kde.kontour @kon 'IANA,[Faure]
application/vnd.kde.kpresenter @kpr,kpt 'IANA,[Faure]
application/vnd.kde.kspread @ksp 'IANA,[Faure]
application/vnd.kde.kword @kwd,kwt 'IANA,[Faure]
application/vnd.kenameaapp @htke 'IANA,[DiGiorgio-Haag]
application/vnd.kidspiration @kia 'IANA,[Bennett]
application/vnd.Kinar @kne,knp,sdf 'IANA,[Thakkar]
application/vnd.koan 'IANA,[Cole]
application/vnd.kodak-descriptor 'IANA,[Donahue]
application/vnd.liberty-request+xml 'IANA,[McDowell]
application/vnd.llamagraphics.life-balance.desktop @lbd 'IANA,[White]
application/vnd.llamagraphics.life-balance.exchange+xml @lbe 'IANA,[White]
application/vnd.lotus-1-2-3 @wks,123 'IANA,[Wattenberger]
application/vnd.lotus-approach 'IANA,[Wattenberger]
application/vnd.lotus-freelance 'IANA,[Wattenberger]
application/vnd.lotus-notes 'IANA,[Laramie]
application/vnd.lotus-organizer 'IANA,[Wattenberger]
application/vnd.lotus-screencam 'IANA,[Wattenberger]
application/vnd.lotus-wordpro 'IANA,[Wattenberger]
application/vnd.macports.portpkg 'IANA,[Berry]
application/vnd.marlin.drm.actiontoken+xml 'IANA,[Ellison]
application/vnd.marlin.drm.conftoken+xml 'IANA,[Ellison]
application/vnd.marlin.drm.license+xml 'IANA,[Ellison]
application/vnd.marlin.drm.mdcf 'IANA,[Ellison]
application/vnd.mcd @mcd 'IANA,[Gotoh]
application/vnd.medcalcdata 'IANA,[Schoonjans]
application/vnd.mediastation.cdkey 'IANA,[Flurry]
application/vnd.meridian-slingshot 'IANA,[Wedel]
application/vnd.MFER 'IANA,[Hirai]
application/vnd.mfmp @mfm 'IANA,[Ikeda]
application/vnd.micrografx.flo @flo 'IANA,[Prevo]
application/vnd.micrografx.igx @igx 'IANA,[Prevo]
application/vnd.mif @mif 'IANA,[Wexler]
application/vnd.minisoft-hp3000-save 'IANA,[Bartram]
application/vnd.mitsubishi.misty-guard.trustweb 'IANA,[Tanaka]
application/vnd.Mobius.DAF 'IANA,[Kabayama]
application/vnd.Mobius.DIS 'IANA,[Kabayama]
application/vnd.Mobius.MBK 'IANA,[Devasia]
application/vnd.Mobius.MQY 'IANA,[Devasia]
application/vnd.Mobius.MSL 'IANA,[Kabayama]
application/vnd.Mobius.PLC 'IANA,[Kabayama]
application/vnd.Mobius.TXF 'IANA,[Kabayama]
application/vnd.mophun.application @mpn 'IANA,[Wennerstrom]
application/vnd.mophun.certificate @mpc 'IANA,[Wennerstrom]
application/vnd.motorola.flexsuite 'IANA,[Patton]
application/vnd.motorola.flexsuite.adsi 'IANA,[Patton]
application/vnd.motorola.flexsuite.fis 'IANA,[Patton]
application/vnd.motorola.flexsuite.gotap 'IANA,[Patton]
application/vnd.motorola.flexsuite.kmr 'IANA,[Patton]
application/vnd.motorola.flexsuite.ttc 'IANA,[Patton]
application/vnd.motorola.flexsuite.wem 'IANA,[Patton]
application/vnd.motorola.iprm 'IANA,[Shamsaasef]
application/vnd.mozilla.xul+xml @xul 'IANA,[McDaniel]
application/vnd.ms-artgalry @cil 'IANA,[Slawson]
application/vnd.ms-asf @asf 'IANA,[Fleischman]
application/vnd.ms-cab-compressed @cab 'IANA,[Scarborough]
application/vnd.ms-excel @xls,xlt :base64 'IANA,[Gill]
application/vnd.ms-fontobject 'IANA,[Scarborough]
application/vnd.ms-ims 'IANA,[Ledoux]
application/vnd.ms-lrm @lrm 'IANA,[Ledoux]
application/vnd.ms-playready.initiator+xml 'IANA,[Schneider]
application/vnd.ms-powerpoint @ppt,pps,pot :base64 'IANA,[Gill]
application/vnd.ms-project @mpp :base64 'IANA,[Gill]
application/vnd.ms-tnef :base64 'IANA,[Gill]
application/vnd.ms-wmdrm.lic-chlg-req 'IANA,[Lau]
application/vnd.ms-wmdrm.lic-resp 'IANA,[Lau]
application/vnd.ms-wmdrm.meter-chlg-req 'IANA,[Lau]
application/vnd.ms-wmdrm.meter-resp 'IANA,[Lau]
application/vnd.ms-works :base64 'IANA,[Gill]
application/vnd.ms-wpl @wpl :base64 'IANA,[Plastina]
application/vnd.ms-xpsdocument @xps :8bit 'IANA,[McGatha]
application/vnd.mseq @mseq 'IANA,[Le Bodic]
application/vnd.msign 'IANA,[Borcherding]
application/vnd.multiad.creator 'IANA,[Mills]
application/vnd.multiad.creator.cif 'IANA,[Mills]
application/vnd.music-niff 'IANA,[Butler]
application/vnd.musician 'IANA,[Adams]
application/vnd.muvee.style 'IANA,[Anantharamu]
application/vnd.ncd.control 'IANA,[Tarkkala]
application/vnd.ncd.reference 'IANA,[Tarkkala]
application/vnd.nervana @ent,entity,req,request,bkm,kcm 'IANA,[Judkins]
application/vnd.netfpx 'IANA,[Mutz]
application/vnd.neurolanguage.nlu 'IANA,[DuFeu]
application/vnd.noblenet-directory 'IANA,[Solomon]
application/vnd.noblenet-sealer 'IANA,[Solomon]
application/vnd.noblenet-web 'IANA,[Solomon]
application/vnd.nokia.catalogs 'IANA,[Nokia]
application/vnd.nokia.conml+wbxml 'IANA,[Nokia]
application/vnd.nokia.conml+xml 'IANA,[Nokia]
application/vnd.nokia.iptv.config+xml 'IANA,[Nokia]
application/vnd.nokia.iSDS-radio-presets 'IANA,[Nokia]
application/vnd.nokia.landmark+wbxml 'IANA,[Nokia]
application/vnd.nokia.landmark+xml 'IANA,[Nokia]
application/vnd.nokia.landmarkcollection+xml 'IANA,[Nokia]
application/vnd.nokia.n-gage.ac+xml 'IANA,[Nokia]
application/vnd.nokia.n-gage.data 'IANA,[Nokia]
application/vnd.nokia.n-gage.symbian.install 'IANA,[Nokia]
application/vnd.nokia.ncd+xml 'IANA,[Nokia]
application/vnd.nokia.pcd+wbxml 'IANA,[Nokia]
application/vnd.nokia.pcd+xml 'IANA,[Nokia]
application/vnd.nokia.radio-preset @rpst 'IANA,[Nokia]
application/vnd.nokia.radio-presets @rpss 'IANA,[Nokia]
application/vnd.novadigm.EDM 'IANA,[Swenson]
application/vnd.novadigm.EDX 'IANA,[Swenson]
application/vnd.novadigm.EXT 'IANA,[Swenson]
application/vnd.oasis.opendocument.chart @odc 'IANA,[Oppermann]
application/vnd.oasis.opendocument.chart-template @odc 'IANA,[Oppermann]
application/vnd.oasis.opendocument.database @odb 'IANA,[Schubert],[Oasis OpenDocument TC=OASIS OpenDocumentTC]
application/vnd.oasis.opendocument.formula @odf 'IANA,[Oppermann]
application/vnd.oasis.opendocument.formula-template @odf 'IANA,[Oppermann]
application/vnd.oasis.opendocument.graphics @odg 'IANA,[Oppermann]
application/vnd.oasis.opendocument.graphics-template @otg 'IANA,[Oppermann]
application/vnd.oasis.opendocument.image @odi 'IANA,[Oppermann]
application/vnd.oasis.opendocument.image-template @odi 'IANA,[Oppermann]
application/vnd.oasis.opendocument.presentation @odp 'IANA,[Oppermann]
application/vnd.oasis.opendocument.presentation-template @otp 'IANA,[Oppermann]
application/vnd.oasis.opendocument.spreadsheet @ods 'IANA,[Oppermann]
application/vnd.oasis.opendocument.spreadsheet-template @ots 'IANA,[Oppermann]
application/vnd.oasis.opendocument.text @odt 'IANA,[Oppermann]
application/vnd.oasis.opendocument.text-master @odm 'IANA,[Oppermann]
application/vnd.oasis.opendocument.text-template @ott 'IANA,[Oppermann]
application/vnd.oasis.opendocument.text-web @oth 'IANA,[Oppermann]
application/vnd.obn 'IANA,[Hessling]
application/vnd.olpc-sugar 'IANA,[Palmieri]
application/vnd.oma-scws-config 'IANA,[Mahalal]
application/vnd.oma-scws-http-request 'IANA,[Mahalal]
application/vnd.oma-scws-http-response 'IANA,[Mahalal]
application/vnd.oma.bcast.associated-procedure-parameter+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.drm-trigger+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.imd+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.ltkm 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.notification+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.provisioningtrigger 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.sgboot 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.sgdd+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.sgdu 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.simple-symbol-container 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.smartcard-trigger+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.sprov+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.bcast.stkm 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.dcd 'IANA,[Primo],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.dcdc 'IANA,[Primo],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.dd2+xml 'IANA,[Sato],[Open Mobile Alliance's BAC DLDRM Working Group]
application/vnd.oma.drm.risd+xml 'IANA,[Rauschenbach],[OMNA - Open Mobile Naming Authority=OMNA-OpenMobileNamingAuthority]
application/vnd.oma.group-usage-list+xml 'IANA,[Kelley],[OMA Presence and Availability (PAG) Working Group]
application/vnd.oma.poc.detailed-progress-report+xml 'IANA,[OMA Push to Talk over Cellular (POC) Working Group]
application/vnd.oma.poc.final-report+xml 'IANA,[OMA Push to Talk over Cellular (POC) Working Group]
application/vnd.oma.poc.groups+xml 'IANA,[Kelley],[OMA Push to Talk over Cellular (POC) Working Group]
application/vnd.oma.poc.invocation-descriptor+xml 'IANA,[OMA Push to Talk over Cellular (POC) Working Group]
application/vnd.oma.poc.optimized-progress-report+xml 'IANA,[OMA Push to Talk over Cellular (POC) Working Group]
application/vnd.oma.xcap-directory+xml 'IANA,[Kelley],[OMA Presence and Availability (PAG) Working Group]
application/vnd.omads-email+xml 'IANA,[OMA Data Synchronization Working Group]
application/vnd.omads-file+xml 'IANA,[OMA Data Synchronization Working Group]
application/vnd.omads-folder+xml 'IANA,[OMA Data Synchronization Working Group]
application/vnd.omaloc-supl-init 'IANA,[Grange]
application/vnd.openofficeorg.extension 'IANA,[Lingner]
application/vnd.osa.netdeploy 'IANA,[Klos]
application/vnd.osgi.bundle 'IANA,[Kriens]
application/vnd.osgi.dp 'IANA,[Kriens]
application/vnd.otps.ct-kip+xml 'IANA,[Nyström=Nystrom]
application/vnd.palm @prc,pdb,pqa,oprc :base64 'IANA,[Peacock]
application/vnd.paos.xml 'IANA,[Kemp]
application/vnd.pg.format 'IANA,[Gandert]
application/vnd.pg.osasli 'IANA,[Gandert]
application/vnd.piaccess.application-licence 'IANA,[Maneos]
application/vnd.picsel @efif 'IANA,[Naccarato]
application/vnd.poc.group-advertisement+xml 'IANA,[Kelley],[OMA Push to Talk over Cellular (POC) Working Group]
application/vnd.pocketlearn 'IANA,[Pando]
application/vnd.powerbuilder6 'IANA,[Guy]
application/vnd.powerbuilder6-s 'IANA,[Guy]
application/vnd.powerbuilder7 'IANA,[Shilts]
application/vnd.powerbuilder7-s 'IANA,[Shilts]
application/vnd.powerbuilder75 'IANA,[Shilts]
application/vnd.powerbuilder75-s 'IANA,[Shilts]
application/vnd.preminet 'IANA,[Tenhunen]
application/vnd.previewsystems.box 'IANA,[Smolgovsky]
application/vnd.proteus.magazine 'IANA,[Hoch]
application/vnd.publishare-delta-tree 'IANA,[Ben-Kiki]
application/vnd.pvi.ptid1 @pti,ptid 'IANA,[Lamb]
application/vnd.pwg-multiplexed 'IANA,RFC3391
application/vnd.pwg-xhtml-print+xml 'IANA,[Wright]
application/vnd.qualcomm.brew-app-res 'IANA,[Forrester]
application/vnd.Quark.QuarkXPress @qxd,qxt,qwd,qwt,qxl,qxb :8bit 'IANA,[Scheidler]
application/vnd.rapid 'IANA,[Szekely]
application/vnd.recordare.musicxml 'IANA,[Good]
application/vnd.recordare.musicxml+xml 'IANA,[Good]
application/vnd.RenLearn.rlprint 'IANA,[Wick]
application/vnd.route66.link66+xml 'IANA,[Kikstra]
application/vnd.ruckus.download 'IANA,[Harris]
application/vnd.s3sms 'IANA,[Tarkkala]
application/vnd.sbm.cid 'IANA,[Kusakari]
application/vnd.sbm.mid2 'IANA,[Murai]
application/vnd.scribus 'IANA,[Bradney]
application/vnd.sealed.3df 'IANA,[Kwan]
application/vnd.sealed.csf 'IANA,[Kwan]
application/vnd.sealed.doc @sdoc,sdo,s1w 'IANA,[Petersen]
application/vnd.sealed.eml @seml,sem 'IANA,[Petersen]
application/vnd.sealed.mht @smht,smh 'IANA,[Petersen]
application/vnd.sealed.net 'IANA,[Lambert]
application/vnd.sealed.ppt @sppt,spp,s1p 'IANA,[Petersen]
application/vnd.sealed.tiff 'IANA,[Kwan],[Lambert]
application/vnd.sealed.xls @sxls,sxl,s1e 'IANA,[Petersen]
application/vnd.sealedmedia.softseal.html @stml,stm,s1h 'IANA,[Petersen]
application/vnd.sealedmedia.softseal.pdf @spdf,spd,s1a 'IANA,[Petersen]
application/vnd.seemail @see 'IANA,[Webb]
application/vnd.sema 'IANA,[Hansson]
application/vnd.semd 'IANA,[Hansson]
application/vnd.semf 'IANA,[Hansson]
application/vnd.shana.informed.formdata 'IANA,[Selzler]
application/vnd.shana.informed.formtemplate 'IANA,[Selzler]
application/vnd.shana.informed.interchange 'IANA,[Selzler]
application/vnd.shana.informed.package 'IANA,[Selzler]
application/vnd.SimTech-MindMapper 'IANA,[Koh]
application/vnd.smaf @mmf 'IANA,[Takahashi]
application/vnd.smart.teacher 'IANA,[Boyle]
application/vnd.software602.filler.form+xml 'IANA,[Hytka],[Vondrous]
application/vnd.software602.filler.form-xml-zip 'IANA,[Hytka],[Vondrous]
application/vnd.solent.sdkm+xml 'IANA,[Gauntlett]
application/vnd.spotfire.dxp 'IANA,[Jernberg]
application/vnd.spotfire.sfs 'IANA,[Jernberg]
application/vnd.sss-cod 'IANA,[Dani]
application/vnd.sss-dtf 'IANA,[Bruno]
application/vnd.sss-ntf 'IANA,[Bruno]
application/vnd.street-stream 'IANA,[Levitt]
application/vnd.sun.wadl+xml 'IANA,[Hadley]
application/vnd.sus-calendar @sus,susp 'IANA,[Niedfeldt]
application/vnd.svd 'IANA,[Becker]
application/vnd.swiftview-ics 'IANA,[Widener]
application/vnd.syncml+xml 'IANA,[OMA Data Synchronization Working Group]
application/vnd.syncml.dm+wbxml 'IANA,[OMA-DM Work Group]
application/vnd.syncml.dm+xml 'IANA,[Rao],[OMA-DM Work Group]
application/vnd.syncml.ds.notification 'IANA,[OMA Data Synchronization Working Group]
application/vnd.tao.intent-module-archive 'IANA,[Shelton]
application/vnd.tmobile-livetv 'IANA,[Helin]
application/vnd.trid.tpt 'IANA,[Cusack]
application/vnd.triscape.mxs 'IANA,[Simonoff]
application/vnd.trueapp 'IANA,[Hepler]
application/vnd.truedoc 'IANA,[Chase]
application/vnd.ufdl 'IANA,[Manning]
application/vnd.uiq.theme 'IANA,[Ocock]
application/vnd.umajin 'IANA,[Riden]
application/vnd.unity 'IANA,[Unity3d]
application/vnd.uoml+xml 'IANA,[Gerdes]
application/vnd.uplanet.alert 'IANA,[Martin]
application/vnd.uplanet.alert-wbxml 'IANA,[Martin]
application/vnd.uplanet.bearer-choice 'IANA,[Martin]
application/vnd.uplanet.bearer-choice-wbxml 'IANA,[Martin]
application/vnd.uplanet.cacheop 'IANA,[Martin]
application/vnd.uplanet.cacheop-wbxml 'IANA,[Martin]
application/vnd.uplanet.channel 'IANA,[Martin]
application/vnd.uplanet.channel-wbxml 'IANA,[Martin]
application/vnd.uplanet.list 'IANA,[Martin]
application/vnd.uplanet.list-wbxml 'IANA,[Martin]
application/vnd.uplanet.listcmd 'IANA,[Martin]
application/vnd.uplanet.listcmd-wbxml 'IANA,[Martin]
application/vnd.uplanet.signal 'IANA,[Martin]
application/vnd.vcx 'IANA,[T.Sugimoto]
application/vnd.vd-study 'IANA,[Rogge]
application/vnd.vectorworks 'IANA,[Ferguson],[Sarkar]
application/vnd.vidsoft.vidconference @vsc :8bit 'IANA,[Hess]
application/vnd.visio @vsd,vst,vsw,vss 'IANA,[Sandal]
application/vnd.visionary @vis 'IANA,[Aravindakumar]
application/vnd.vividence.scriptfile 'IANA,[Risher]
application/vnd.vsf 'IANA,[Rowe]
application/vnd.wap.sic @sic 'IANA,[WAP-Forum]
application/vnd.wap.slc @slc 'IANA,[WAP-Forum]
application/vnd.wap.wbxml @wbxml 'IANA,[Stark]
application/vnd.wap.wmlc @wmlc 'IANA,[Stark]
application/vnd.wap.wmlscriptc @wmlsc 'IANA,[Stark]
application/vnd.webturbo @wtb 'IANA,[Rehem]
application/vnd.wfa.wsc 'IANA,[Wi-Fi Alliance]
application/vnd.wmc 'IANA,[Kjørnes=Kjornes]
application/vnd.wmf.bootstrap 'IANA,[Nguyenphu],[Iyer]
application/vnd.wordperfect @wpd 'IANA,[Scarborough]
application/vnd.wqd @wqd 'IANA,[Bostrom]
application/vnd.wrq-hp3000-labelled 'IANA,[Bartram]
application/vnd.wt.stf 'IANA,[Wohler]
application/vnd.wv.csp+wbxml @wv 'IANA,[Salmi]
application/vnd.wv.csp+xml :8bit 'IANA,[Ingimundarson]
application/vnd.wv.ssp+xml :8bit 'IANA,[Ingimundarson]
application/vnd.xara 'IANA,[Matthewman]
application/vnd.xfdl 'IANA,[Manning]
application/vnd.xfdl.webform 'IANA,[Mansell]
application/vnd.xmi+xml 'IANA,[Waskiewicz]
application/vnd.xmpie.cpkg 'IANA,[Sherwin]
application/vnd.xmpie.dpkg 'IANA,[Sherwin]
application/vnd.xmpie.plan 'IANA,[Sherwin]
application/vnd.xmpie.ppkg 'IANA,[Sherwin]
application/vnd.xmpie.xlim 'IANA,[Sherwin]
application/vnd.yamaha.hv-dic @hvd 'IANA,[Yamamoto]
application/vnd.yamaha.hv-script @hvs 'IANA,[Yamamoto]
application/vnd.yamaha.hv-voice @hvp 'IANA,[Yamamoto]
application/vnd.yamaha.smaf-audio @saf 'IANA,[Shinoda]
application/vnd.yamaha.smaf-phrase @spf 'IANA,[Shinoda]
application/vnd.yellowriver-custom-menu 'IANA,[Yellow]
application/vnd.zul 'IANA,[Grothmann]
application/vnd.zzazz.deck+xml 'IANA,[Hewett]
application/voicexml+xml 'IANA,RFC4267
application/watcherinfo+xml @wif 'IANA,RFC3858
application/whoispp-query 'IANA,RFC2957
application/whoispp-response 'IANA,RFC2958
application/wita 'IANA,[Campbell]
application/wordperfect5.1 @wp5,wp 'IANA,[Lindner]
application/wsdl+xml 'IANA,[W3C]
application/wspolicy+xml 'IANA,[W3C]
application/x400-bp 'IANA,RFC1494
application/xcap-att+xml 'IANA,RFC4825
application/xcap-caps+xml 'IANA,RFC4825
application/xcap-el+xml 'IANA,RFC4825
application/xcap-error+xml 'IANA,RFC4825
application/xcap-ns+xml 'IANA,RFC4825
application/xenc+xml 'IANA,[Reagle],[XENC Working Group]
application/xhtml+xml @xhtml :8bit 'IANA,RFC3236
application/xml @xml,xsl :8bit 'IANA,RFC3023
application/xml-dtd @dtd :8bit 'IANA,RFC3023
application/xml-external-parsed-entity 'IANA,RFC3023
application/xmpp+xml 'IANA,RFC3923
application/xop+xml 'IANA,[Nottingham]
application/xv+xml 'IANA,RFC4374
application/zip @zip :base64 'IANA,[Lindner]

*mac:application/x-mac @bin :base64
*mac:application/x-macbase64 @bin :base64

!application/smil @smi,smil :8bit 'IANA,RFC4536 =use-instead:application/smil+xml
!application/xhtml-voice+xml 'IANA,{RFC-mccobb-xplusv-media-type-04.txt=https://datatracker.ietf.org/public/idindex.cgi?command=id_detail&filename=draft-mccobb-xplusv-media-type}
*!application/VMSBACKUP @bck :base64 =use-instead:application/x-VMSBACKUP
*!application/access @mdf,mda,mdb,mde =use-instead:application/x-msaccess
*!application/bleeper @bleep :base64 =use-instead:application/x-bleeper
*!application/cals1840 'LTSW =use-instead:application/cals-1840
*!application/futuresplash @spl =use-instead:application/x-futuresplash
*!application/ghostview =use-instead:application/x-ghostview
*!application/hep @hep =use-instead:application/x-hep
*!application/imagemap @imagemap,imap :8bit =use-instead:application/x-imagemap
*!application/lotus-123 @wks =use-instead:application/vnd.lotus-1-2-3
*!application/mac-compactpro @cpt =use-instead:application/x-mac-compactpro
*!application/mathcad @mcd :base64 =use-instead:application/vnd.mcd
*!application/mathematica-old =use-instead:application/x-mathematica-old
*!application/news-message-id 'IANA,RFC1036,[Spencer]
*!application/quicktimeplayer @qtl =use-instead:application/x-quicktimeplayer
*!application/remote_printing 'LTSW =use-instead:application/remote-printing
*!application/toolbook @tbk =use-instead:application/x-toolbook
*!application/vnd.ms-excel.sheet.binary.macroEnabled.12 @xlsb
*!application/vnd.ms-excel.sheet.macroEnabled.12 @xlsm
*!application/vnd.ms-word.document.macroEnabled.12 @docm
*!application/vnd.ms-word.template.macroEnabled.12 @dotm
*!application/wordperfect @wp =use-instead:application/vnd.wordperfect
*!application/wordperfect6.1 @wp6 =use-instead:application/x-wordperfect6.1
*!application/wordperfectd @wpd =use-instead:application/vnd.wordperfect
*!application/x-123 @wk =use-instead:application/vnd.lotus-1-2-3
*!application/x-access @mdf,mda,mdb,mde =use-instead:application/x-msaccess
*!application/x-compress @z,Z :base64 =use-instead:application/x-compressed
*!application/x-javascript @js :8bit =use-instead:application/javascript
*!application/x-lotus-123 @wks =use-instead:application/vnd.lotus-1-2-3
*!application/x-mathcad @mcd :base64 =use-instead:application/vnd.mcd
*!application/x-msword @doc,dot,wrd :base64 =use-instead:application/msword
*!application/x-rtf @rtf :base64 'LTSW =use-instead:application/rtf
*!application/x-troff 'LTSW =use-instead:text/troff
*!application/x-u-star 'LTSW =use-instead:application/x-ustar
*!application/x-word @doc,dot :base64 =use-instead:application/msword
*!application/x-wordperfect @wp =use-instead:application/vnd.wordperfect
*!application/x-wordperfectd @wpd =use-instead:application/vnd.wordperfect
*!application/x400.bp 'LTSW =use-instead:application/x400-bp
*application/SLA 'LTSW
*application/STEP 'LTSW
*application/acad 'LTSW
*application/appledouble :base64
*application/clariscad 'LTSW
*application/drafting 'LTSW
*application/dxf 'LTSW
*application/excel @xls,xlt 'LTSW
*application/fractals 'LTSW
*application/i-deas 'LTSW
*application/macbinary 'LTSW
*application/netcdf @nc,cdf 'LTSW
*application/powerpoint @ppt,pps,pot :base64 'LTSW
*application/pro_eng 'LTSW
*application/set 'LTSW
*application/solids 'LTSW
*application/vda 'LTSW
*application/vnd.openxmlformats-officedocument.presentationml.presentation @pptx
*application/vnd.openxmlformats-officedocument.presentationml.slideshow @ppsx
*application/vnd.openxmlformats-officedocument.spreadsheetml.sheet @xlsx :quoted-printable
*application/vnd.openxmlformats-officedocument.wordprocessingml.document @docx
*application/vnd.openxmlformats-officedocument.wordprocessingml.template @dotx
*application/vnd.stardivision.calc @sdc
*application/vnd.stardivision.chart @sds
*application/vnd.stardivision.draw @sda
*application/vnd.stardivision.impress @sdd
*application/vnd.stardivision.math @sdf
*application/vnd.stardivision.writer @sdw
*application/vnd.stardivision.writer-global @sgl
*application/vnd.street-stream 'IANA,[Levitt]
*application/vnd.sun.wadl+xml 'IANA,[Hadley]
*application/vnd.sun.xml.calc @sxc
*application/vnd.sun.xml.calc.template @stc
*application/vnd.sun.xml.draw @sxd
*application/vnd.sun.xml.draw.template @std
*application/vnd.sun.xml.impress @sxi
*application/vnd.sun.xml.impress.template @sti
*application/vnd.sun.xml.math @sxm
*application/vnd.sun.xml.writer @sxw
*application/vnd.sun.xml.writer.global @sxg
*application/vnd.sun.xml.writer.template @stw
*application/word @doc,dot 'LTSW
*application/x-SLA
*application/x-STEP
*application/x-VMSBACKUP @bck :base64
*application/x-Wingz @wz
*application/x-bcpio @bcpio 'LTSW
*application/x-bleeper @bleep :base64
*application/x-bzip2 @bz2
*application/x-cdlink @vcd
*application/x-chess-pgn @pgn
*application/x-clariscad
*application/x-compressed @z,Z :base64 'LTSW
*application/x-cpio @cpio :base64 'LTSW
*application/x-csh @csh :8bit 'LTSW
*application/x-cu-seeme @csm,cu
*application/x-debian-package @deb
*application/x-director @dcr,@dir,@dxr
*application/x-drafting
*application/x-dvi @dvi :base64 'LTSW
*application/x-dxf
*application/x-excel
*application/x-fractals
*application/x-futuresplash @spl
*application/x-ghostview
*application/x-gtar @gtar,tgz,tbz2,tbz :base64 'LTSW
*application/x-gzip @gz :base64 'LTSW
*application/x-hdf @hdf 'LTSW
*application/x-hep @hep
*application/x-html+ruby @rhtml :8bit
*application/x-httpd-php @phtml,pht,php :8bit
*application/x-ica @ica
*application/x-ideas
*application/x-imagemap @imagemap,imap :8bit
*application/x-java-archive @jar 'LTSW
*application/x-java-jnlp-file @jnlp 'LTSW
*application/x-java-serialized-object @ser 'LTSW
*application/x-java-vm @class 'LTSW
*application/x-koan @skp,skd,skt,skm
*application/x-latex @ltx,latex :8bit 'LTSW
*application/x-mac-compactpro @cpt
*application/x-macbinary
*application/x-maker @frm,maker,frame,fm,fb,book,fbdoc =use-instead:application/vnd.framemaker
*application/x-mathematica-old
*application/x-mif @mif 'LTSW
*application/x-msaccess @mda,mdb,mde,mdf
*application/x-msdos-program @cmd,bat :8bit
*application/x-msdos-program @com,exe :base64
*application/x-msdownload @exe,com :base64
*application/x-netcdf @nc,cdf
*application/x-ns-proxy-autoconfig @pac
*application/x-pagemaker @pm,pm5,pt5
*application/x-perl @pl,pm :8bit
*application/x-pgp
*application/x-python @py :8bit
*application/x-quicktimeplayer @qtl
*application/x-rar-compressed @rar :base64
*application/x-remote_printing
*application/x-ruby @rb,rbw :8bit
*application/x-set
*application/x-sh @sh :8bit 'LTSW
*application/x-shar @shar :8bit 'LTSW
*application/x-shockwave-flash @swf
*application/x-solids
*application/x-spss @sav,sbs,sps,spo,spp
*application/x-stuffit @sit :base64 'LTSW
*application/x-sv4cpio @sv4cpio :base64 'LTSW
*application/x-sv4crc @sv4crc :base64 'LTSW
*application/x-tar @tar :base64 'LTSW
*application/x-tcl @tcl :8bit 'LTSW
*application/x-tex @tex :8bit
*application/x-texinfo @texinfo,texi :8bit
*application/x-toolbook @tbk
*application/x-troff @t,tr,roff :8bit
*application/x-troff-man @man :8bit 'LTSW
*application/x-troff-me @me 'LTSW
*application/x-troff-ms @ms 'LTSW
*application/x-ustar @ustar :base64 'LTSW
*application/x-wais-source @src 'LTSW
*application/x-wordperfect6.1 @wp6
*application/x-x509-ca-cert @crt :base64
*application/xslt+xml @xslt :8bit

  # audio/*
audio/32kadpcm 'IANA,RFC2421,RFC2422
audio/3gpp @3gpp 'IANA,RFC4281,RFC3839
audio/3gpp2 'IANA,RFC4393,RFC4281
audio/ac3 'IANA,RFC4184
audio/AMR @amr :base64 'RFC4867
audio/AMR-WB @awb :base64 'RFC4867
audio/amr-wb+ 'IANA,RFC4352
audio/asc 'IANA,RFC4695
audio/basic @au,snd :base64 'IANA,RFC2045,RFC2046
audio/BV16 'IANA,RFC4298
audio/BV32 'IANA,RFC4298
audio/clearmode 'IANA,RFC4040
audio/CN 'IANA,RFC3389
audio/DAT12 'IANA,RFC3190
audio/dls 'IANA,RFC4613
audio/dsr-es201108 'IANA,RFC3557
audio/dsr-es202050 'IANA,RFC4060
audio/dsr-es202211 'IANA,RFC4060
audio/dsr-es202212 'IANA,RFC4060
audio/DVI4 'IANA,RFC4856
audio/eac3 'IANA,RFC4598
audio/EVRC @evc 'IANA,RFC4788
audio/EVRC-QCP 'IANA,RFC3625
audio/EVRC0 'IANA,RFC4788
audio/EVRC1 'IANA,RFC4788
audio/EVRCB 'IANA,RFC5188
audio/EVRCB0 'IANA,RFC5188
audio/EVRCB1 'IANA,RFC4788
audio/EVRCWB 'IANA,RFC5188
audio/EVRCWB0 'IANA,RFC5188
audio/EVRCWB1 'IANA,RFC5188
audio/G719 'IANA,RFC5404
audio/G722 'IANA,RFC4856
audio/G7221 'IANA,RFC3047
audio/G723 'IANA,RFC4856
audio/G726-16 'IANA,RFC4856
audio/G726-24 'IANA,RFC4856
audio/G726-32 'IANA,RFC4856
audio/G726-40 'IANA,RFC4856
audio/G728 'IANA,RFC4856
audio/G729 'IANA,RFC4856
audio/G7291 'IANA,RFC4749,RFC5459
audio/G729D 'IANA,RFC4856
audio/G729E 'IANA,RFC4856
audio/GSM 'IANA,RFC4856
audio/GSM-EFR 'IANA,RFC4856
audio/iLBC 'IANA,RFC3952
audio/L16 @l16 'IANA,RFC4856
audio/L20 'IANA,RFC3190
audio/L24 'IANA,RFC3190
audio/L8 'IANA,RFC4856
audio/LPC 'IANA,RFC4856
audio/mobile-xmf 'IANA,RFC4723
audio/mp4 'IANA,RFC4337
audio/MP4A-LATM 'IANA,RFC3016
audio/MPA 'IANA,RFC3555
audio/mpa-robust 'IANA,RFC5219
audio/mpeg @mpga,mp2,mp3 :base64 'IANA,RFC3003
audio/mpeg4-generic 'IANA,RFC3640
audio/ogg 'IANA,RFC5334
audio/parityfec 'IANA,RFC5109
audio/PCMA 'IANA,RFC4856
audio/PCMA-WB 'IANA,RFC5391
audio/PCMU 'IANA,RFC4856
audio/PCMU-WB 'IANA,RFC5391
audio/prs.sid 'IANA,[Walleij]
audio/QCELP 'IANA,RFC3555,RFC3625
audio/RED 'IANA,RFC3555
audio/rtp-enc-aescm128 'IANA,[3GPP]
audio/rtp-midi 'IANA,RFC4695
audio/rtx 'IANA,RFC4588
audio/SMV @smv 'IANA,RFC3558
audio/SMV-QCP 'IANA,RFC3625
audio/SMV0 'IANA,RFC3558
audio/sp-midi 'IANA,[Kosonen],[T. White=T.White]
audio/t140c 'IANA,RFC4351
audio/t38 'IANA,RFC4612
audio/telephone-event 'IANA,RFC4733
audio/tone 'IANA,RFC4733
audio/ulpfec 'IANA,RFC5109
audio/VDVI 'IANA,RFC4856
audio/VMR-WB 'IANA,RFC4348,RFC4424
audio/vnd.3gpp.iufp 'IANA,[Belling]
audio/vnd.4SB 'IANA,[De Jaham]
audio/vnd.audiokoz 'IANA,[DeBarros]
audio/vnd.CELP 'IANA,[De Jaham]
audio/vnd.cisco.nse 'IANA,[Kumar]
audio/vnd.cmles.radio-events 'IANA,[Goulet]
audio/vnd.cns.anp1 'IANA,[McLaughlin]
audio/vnd.cns.inf1 'IANA,[McLaughlin]
audio/vnd.digital-winds @eol :7bit 'IANA,[Strazds]
audio/vnd.dlna.adts 'IANA,[Heredia]
audio/vnd.dolby.mlp 'IANA,[Ward]
audio/vnd.dolby.mps 'IANA,[Hattersley]
audio/vnd.dts 'IANA,[Zou]
audio/vnd.dts.hd 'IANA,[Zou]
audio/vnd.everad.plj @plj 'IANA,[Cicelsky]
audio/vnd.hns.audio 'IANA,[Swaminathan]
audio/vnd.lucent.voice @lvp 'IANA,[Vaudreuil]
audio/vnd.ms-playready.media.pya 'IANA,[DiAcetis]
audio/vnd.nokia.mobile-xmf @mxmf 'IANA,[Nokia Corporation=Nokia]
audio/vnd.nortel.vbk @vbk 'IANA,[Parsons]
audio/vnd.nuera.ecelp4800 @ecelp4800 'IANA,[Fox]
audio/vnd.nuera.ecelp7470 @ecelp7470 'IANA,[Fox]
audio/vnd.nuera.ecelp9600 @ecelp9600 'IANA,[Fox]
audio/vnd.octel.sbc 'IANA,[Vaudreuil]
audio/vnd.rhetorex.32kadpcm 'IANA,[Vaudreuil]
audio/vnd.sealedmedia.softseal.mpeg @smp3,smp,s1m 'IANA,[Petersen]
audio/vnd.vmx.cvsd 'IANA,[Vaudreuil]
audio/vorbis 'IANA,RFC5215
audio/vorbis-config 'IANA,RFC5215

audio/x-aiff @aif,aifc,aiff :base64
audio/x-midi @mid,midi,kar :base64
audio/x-pn-realaudio @rm,ram :base64
audio/x-pn-realaudio-plugin @rpm
audio/x-realaudio @ra :base64
audio/x-wav @wav :base64

!audio/vnd.qcelp @qcp 'IANA,RFC3625 =use-instead:audio/QCELP

  # image/*
image/cgm 'IANA,[Francis]
image/fits 'IANA,RFC4047
image/g3fax 'IANA,RFC1494
image/gif @gif :base64 'IANA,RFC2045,RFC2046
image/ief @ief :base64 'IANA,RFC1314
image/jp2 @jp2,jpg2 :base64 'IANA,RFC3745
image/jpeg @jpeg,jpg,jpe :base64 'IANA,RFC2045,RFC2046
image/jpm @jpm,jpgm :base64 'IANA,RFC3745
image/jpx @jpx,jpf :base64 'IANA,RFC3745
image/naplps 'IANA,[Ferber]
image/png @png :base64 'IANA,[Randers-Pehrson]
image/prs.btif 'IANA,[Simon]
image/prs.pti 'IANA,[Laun]
image/t38 'IANA,RFC3362
image/tiff @tiff,tif :base64 'IANA,RFC2302
image/tiff-fx 'IANA,RFC3950
image/vnd.adobe.photoshop 'IANA,[Scarborough]
image/vnd.cns.inf2 'IANA,[McLaughlin]
image/vnd.djvu @djvu,djv 'IANA,[Bottou]
image/vnd.dwg @dwg 'IANA,[Moline]
image/vnd.dxf 'IANA,[Moline]
image/vnd.fastbidsheet 'IANA,[Becker]
image/vnd.fpx 'IANA,[Spencer]
image/vnd.fst 'IANA,[Fuldseth]
image/vnd.fujixerox.edmics-mmr 'IANA,[Onda]
image/vnd.fujixerox.edmics-rlc 'IANA,[Onda]
image/vnd.globalgraphics.pgb @pgb 'IANA,[Bailey]
image/vnd.microsoft.icon @ico 'IANA,[Butcher]
image/vnd.mix 'IANA,[Reddy]
image/vnd.ms-modi @mdi 'IANA,[Vaughan]
image/vnd.net-fpx 'IANA,[Spencer]
image/vnd.sealed.png @spng,spn,s1n 'IANA,[Petersen]
image/vnd.sealedmedia.softseal.gif @sgif,sgi,s1g 'IANA,[Petersen]
image/vnd.sealedmedia.softseal.jpg @sjpg,sjp,s1j 'IANA,[Petersen]
image/vnd.svf 'IANA,[Moline]
image/vnd.wap.wbmp @wbmp 'IANA,[Stark]
image/vnd.xiff 'IANA,[S.Martin]

*!image/bmp @bmp =use-instead:image/x-bmp
*!image/cmu-raster =use-instead:image/x-cmu-raster
*!image/targa @tga =use-instead:image/x-targa
*!image/vnd.dgn @dgn =use-instead:image/x-vnd.dgn
*!image/vnd.net.fpx =use-instead:image/vnd.net-fpx
*image/pjpeg :base64 =Fixes a bug with IE6 and progressive JPEGs
*image/svg+xml @svg :8bit
*image/x-bmp @bmp
*image/x-cmu-raster @ras
*image/x-paintshoppro @psp,pspimage :base64
*image/x-pict
*image/x-portable-anymap @pnm :base64
*image/x-portable-bitmap @pbm :base64
*image/x-portable-graymap @pgm :base64
*image/x-portable-pixmap @ppm :base64
*image/x-rgb @rgb :base64
*image/x-targa @tga
*image/x-vnd.dgn @dgn
*image/x-win-bmp
*image/x-xbitmap @xbm :7bit
*image/x-xbm @xbm :7bit
*image/x-xpixmap @xpm :8bit
*image/x-xwindowdump @xwd :base64

  # message/*
message/CPIM 'IANA,RFC3862
message/delivery-status 'IANA,RFC1894
message/disposition-notification 'IANA,RFC2298
message/external-body :8bit 'IANA,RFC2045,RFC2046
message/global 'IANA,RFC5335
message/global-delivery-status 'IANA,RFC5337
message/global-disposition-notification 'IANA,RFC5337
message/global-headers 'IANA,RFC5337
message/http 'IANA,RFC2616
message/imdn+xml 'IANA,RFC5438
message/news :8bit 'IANA,RFC1036,[H.Spencer]
message/partial :8bit 'IANA,RFC2045,RFC2046
message/rfc822 @eml :8bit 'IANA,RFC2045,RFC2046
message/s-http 'IANA,RFC2660
message/sip 'IANA,RFC3261
message/sipfrag 'IANA,RFC3420
message/tracking-status 'IANA,RFC3886
message/vnd.si.simp 'IANA,[Parks Young=ParksYoung]

  # model/*
model/iges @igs,iges 'IANA,[Parks]
model/mesh @msh,mesh,silo 'IANA,RFC2077
model/vnd.dwf 'IANA,[Pratt]
model/vnd.flatland.3dml 'IANA,[Powers]
model/vnd.gdl 'IANA,[Babits]
model/vnd.gs-gdl 'IANA,[Babits]
model/vnd.gtw 'IANA,[Ozaki]
model/vnd.moml+xml 'IANA,[Brooks]
model/vnd.mts 'IANA,[Rabinovitch]
model/vnd.parasolid.transmit.binary @x_b,xmt_bin 'IANA,[Parasolid]
model/vnd.parasolid.transmit.text @x_t,xmt_txt :quoted-printable 'IANA,[Parasolid]
model/vnd.vtu 'IANA,[Rabinovitch]
model/vrml @wrl,vrml 'IANA,RFC2077

  # multipart/*
multipart/alternative :8bit 'IANA,RFC2045,RFC2046
multipart/appledouble :8bit 'IANA,[Faltstrom]
multipart/byteranges 'IANA,RFC2068
multipart/digest :8bit 'IANA,RFC2045,RFC2046
multipart/encrypted 'IANA,RFC1847
multipart/form-data 'IANA,RFC2388
multipart/header-set 'IANA,[Crocker]
multipart/mixed :8bit 'IANA,RFC2045,RFC2046
multipart/parallel :8bit 'IANA,RFC2045,RFC2046
multipart/related 'IANA,RFC2387
multipart/report 'IANA,RFC3462
multipart/signed 'IANA,RFC1847
multipart/voice-message 'IANA,RFC2421,RFC2423
*multipart/x-gzip
*multipart/x-mixed-replace
*multipart/x-tar
*multipart/x-ustar
*multipart/x-www-form-urlencoded
*multipart/x-zip
*!multipart/x-parallel =use-instead:multipart/parallel

  # text/*
text/calendar 'IANA,RFC2445
text/css @css :8bit 'IANA,RFC2318
text/csv @csv :8bit 'IANA,RFC4180
text/directory 'IANA,RFC2425
text/dns 'IANA,RFC4027
text/enriched 'IANA,RFC1896
text/html @html,htm,htmlx,shtml,htx :8bit 'IANA,RFC2854
text/parityfec 'IANA,RFC5109
text/plain @txt,asc,c,cc,h,hh,cpp,hpp,dat,hlp 'IANA,RFC2046,RFC3676,RFC5147
text/prs.fallenstein.rst @rst 'IANA,[Fallenstein]
text/prs.lines.tag 'IANA,[Lines]
text/RED 'IANA,RFC4102
text/rfc822-headers 'IANA,RFC3462
text/richtext @rtx :8bit 'IANA,RFC2045,RFC2046
text/rtf @rtf :8bit 'IANA,[Lindner]
text/rtp-enc-aescm128 'IANA,[3GPP]
text/rtx 'IANA,RFC4588
text/sgml @sgml,sgm 'IANA,RFC1874
text/t140 'IANA,RFC4103
text/tab-separated-values @tsv 'IANA,[Lindner]
text/troff @t,tr,roff,troff :8bit 'IANA,RFC4263
text/ulpfec 'IANA,RFC5109
text/uri-list 'IANA,RFC2483
text/vnd.abc 'IANA,[Allen]
text/vnd.curl 'IANA,[Byrnes]
text/vnd.DMClientScript 'IANA,[Bradley]
text/vnd.esmertec.theme-descriptor 'IANA,[Eilemann]
text/vnd.fly 'IANA,[Gurney]
text/vnd.fmi.flexstor 'IANA,[Hurtta]
text/vnd.graphviz 'IANA,[Ellson]
text/vnd.in3d.3dml 'IANA,[Powers]
text/vnd.in3d.spot 'IANA,[Powers]
text/vnd.IPTC.NewsML 'IANA,[IPTC]
text/vnd.IPTC.NITF 'IANA,[IPTC]
text/vnd.latex-z 'IANA,[Lubos]
text/vnd.motorola.reflex 'IANA,[Patton]
text/vnd.ms-mediapackage 'IANA,[Nelson]
text/vnd.net2phone.commcenter.command @ccc 'IANA,[Xie]
text/vnd.si.uricatalogue 'IANA,[Parks Young=ParksYoung]
text/vnd.sun.j2me.app-descriptor @jad :8bit 'IANA,[G.Adams]
text/vnd.trolltech.linguist 'IANA,[D.Lambert]
text/vnd.wap.si @si 'IANA,[WAP-Forum]
text/vnd.wap.sl @sl 'IANA,[WAP-Forum]
text/vnd.wap.wml @wml 'IANA,[Stark]
text/vnd.wap.wmlscript @wmls 'IANA,[Stark]
text/xml @xml,dtd :8bit 'IANA,RFC3023
text/xml-external-parsed-entity 'IANA,RFC3023

vms:text/plain @doc :8bit

!text/ecmascript 'IANA,RFC4329
!text/javascript 'IANA,RFC4329
*!text/comma-separated-values @csv :8bit =use-instead:text/csv
*!text/vnd.flatland.3dml =use-instead:model/vnd.flatland.3dml
*!text/x-rtf @rtf :8bit =use-instead:text/rtf
*!text/x-vnd.flatland.3dml =use-instead:model/vnd.flatland.3dml
*text/x-component @htc :8bit
*text/x-setext @etx
*text/x-vcalendar @vcs :8bit
*text/x-vcard @vcf :8bit
*text/x-yaml @yaml,yml :8bit

  # Registered: video/*
video/3gpp @3gp,3gpp 'IANA,RFC3839,RFC4281
video/3gpp-tt 'IANA,RFC4396
video/3gpp2 'IANA,RFC4393,RFC4281
video/BMPEG 'IANA,RFC3555
video/BT656 'IANA,RFC3555
video/CelB 'IANA,RFC3555
video/DV 'IANA,RFC3189
video/H261 'IANA,RFC4587
video/H263 'IANA,RFC3555
video/H263-1998 'IANA,RFC4629
video/H263-2000 'IANA,RFC4629
video/H264 'IANA,RFC3984
video/JPEG 'IANA,RFC3555
video/jpeg2000 'IANA,RFC5371,RFC5372
video/MJ2 @mj2,mjp2 'IANA,RFC3745
video/MP1S 'IANA,RFC3555
video/MP2P 'IANA,RFC3555
video/MP2T 'IANA,RFC3555
video/mp4 'IANA,RFC4337
video/MP4V-ES 'IANA,RFC3016
video/mpeg @mp2,mpe,mp3g,mpg :base64 'IANA,RFC2045,RFC2046
video/mpeg4-generic 'IANA,RFC3640
video/MPV 'IANA,RFC3555
video/nv 'IANA,RFC4856
video/ogg @ogv 'IANA,RFC5334
video/parityfec 'IANA,RFC5109
video/pointer 'IANA,RFC2862
video/quicktime @qt,mov :base64 'IANA,[Lindner]
video/raw 'IANA,RFC4175
video/rtp-enc-aescm128 'IANA,[3GPP]
video/rtx 'IANA,RFC4588
video/SMPTE292M 'IANA,RFC3497
video/ulpfec 'IANA,RFC5109
video/vc1 'IANA,RFC4425
video/vnd.CCTV 'IANA,[Rottmann]
video/vnd.fvt 'IANA,[Fuldseth]
video/vnd.hns.video 'IANA,[Swaminathan]
video/vnd.iptvforum.1dparityfec-1010 'IANA,[Nakamura]
video/vnd.iptvforum.1dparityfec-2005 'IANA,[Nakamura]
video/vnd.iptvforum.2dparityfec-1010 'IANA,[Nakamura]
video/vnd.iptvforum.2dparityfec-2005 'IANA,[Nakamura]
video/vnd.iptvforum.ttsavc 'IANA,[Nakamura]
video/vnd.iptvforum.ttsmpeg2 'IANA,[Nakamura]
video/vnd.motorola.video 'IANA,[McGinty]
video/vnd.motorola.videop 'IANA,[McGinty]
video/vnd.mpegurl @mxu,m4u :8bit 'IANA,[Recktenwald]
video/vnd.ms-playready.media.pyv 'IANA,[DiAcetis]
video/vnd.nokia.interleaved-multimedia @nim 'IANA,[Kangaslampi]
video/vnd.objectvideo @mp4 'IANA,[Clark]
video/vnd.sealed.mpeg1 @s11 'IANA,[Petersen]
video/vnd.sealed.mpeg4 @smpg,s14 'IANA,[Petersen]
video/vnd.sealed.swf @sswf,ssw 'IANA,[Petersen]
video/vnd.sealedmedia.softseal.mov @smov,smo,s1q 'IANA,[Petersen]
video/vnd.vivo @viv,vivo 'IANA,[Wolfe]

*!video/dl @dl :base64 =use-instead:video/x-dl
*!video/gl @gl :base64 =use-instead:video/x-gl
*!video/vnd.dlna.mpeg-tts 'IANA,[Heredia]
*video/x-dl @dl :base64
*video/x-fli @fli :base64
*video/x-flv @flv :base64
*video/x-gl @gl :base64
*video/x-ms-asf @asf,asx
*video/x-ms-wmv @wmv
*video/x-msvideo @avi :base64
*video/x-sgi-movie @movie :base64

  # Unregistered: other/*
*!chemical/x-pdb @pdb =use-instead:x-chemical/x-pdb
*!chemical/x-xyz @xyz =use-instead:x-chemical/x-xyz
*!drawing/dwf @dwf =use-instead:x-drawing/dwf
x-chemical/x-pdb @pdb
x-chemical/x-xyz @xyz
x-conference/x-cooltalk @ice
x-drawing/dwf @dwf
x-world/x-vrml @wrl,vrml
MIME_TYPES

_re = %r{
  ^
  ([*])?                                # 0: Unregistered?
  (!)?                                  # 1: Obsolete?
  (?:(\w+):)?                           # 2: Platform marker
  #{MIME::Type::MEDIA_TYPE_RE}          # 3,4: Media type
  (?:\s@([^\s]+))?                      # 5: Extensions
  (?:\s:(#{MIME::Type::ENCODING_RE}))?  # 6: Encoding
  (?:\s'(.+))?                          # 7: URL list
  (?:\s=(.+))?                          # 8: Documentation
  $
}x

data_mime_type.split($/).each_with_index do |i, x|
  item = i.chomp.strip.gsub(%r{#.*}o, '')
  next if item.empty?

  begin
    m = _re.match(item).captures
  rescue Exception => ex
    puts <<-"ERROR"
#{__FILE__}:#{x + data_mime_type_first_line}: Parsing error in MIME type definitions.
=> "#{item}"
    ERROR
    raise
  end

  unregistered, obsolete, platform, mediatype, subtype, extensions,
    encoding, urls, docs = *m

  extensions &&= extensions.split(/,/)
  urls &&= urls.split(/,/)

  mime_type = MIME::Type.new("#{mediatype}/#{subtype}") do |t|
    t.extensions  = extensions
    t.encoding    = encoding
    t.system      = platform
    t.obsolete    = obsolete
    t.registered  = false if unregistered
    t.docs        = docs
    t.url         = urls
  end

  MIME::Types.add_type_variant(mime_type)
  MIME::Types.index_extensions(mime_type)
end

_re = data_mime_type = data_mime_type_first_line = nil

