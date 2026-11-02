# frozen_string_literal: true

module Constrict
  # Ported from upstream's po/ directory, together with the gettext imports at
  # the top of src/*.py (`from gettext import gettext as _`, `from gettext
  # import ngettext`) and the `C_()` calls blueprint compiles into
  # g_dpgettext2 in src/gtk/shortcuts-dialog.blp.
  #
  # Upstream hands the work to the C library: meson compiles po/*.po into .mo
  # catalogues, installs them under /usr/share/locale, and GLib's `_()` macro
  # and Python's gettext module both read them back. Neither half of that is
  # available here — the Ruby GLib bindings wrap neither bindtextdomain nor
  # dgettext, and a gem is installed by unpacking it rather than by running
  # msgfmt — so the .po files travel inside the gem (the gemspec packages
  # po/**/*) and are read straight from there.
  #
  # The three entry points keep upstream's names, so a ported call site reads
  # the same as the Python it came from:
  #
  #   _("Constrict")                             # a message
  #   ngettext("{} hour", "{} hours", hours)     # a message chosen by count
  #   C_("shortcut window", "Open")              # a message in a context
  #
  # A class that shows text includes this module; a module_function module
  # extends it.
  module I18n
    # The directory the .po files live in, resolved against this file so it
    # works from a git checkout and from an unpacked gem alike.
    PO_DIR = File.expand_path("../../po", __dir__)

    # A Plural-Forms expression may only mention the count, integer literals,
    # parentheses and the operators gettext's plural grammar allows. The
    # catalogues ship with the port rather than coming from the user, but they
    # are still data files, and this stops the evaluation below from reaching
    # anything that is not arithmetic.
    SAFE_PLURAL_EXPRESSION = %r{\A[\sn\d()?:%!=<>&|+*/-]+\z}

    # Fallbacks for a catalogue whose Plural-Forms header is missing or
    # unreadable: one form for languages that do not inflect by number, and
    # English's one/other split for everything else.
    SINGULAR_ONLY = ->(_count) { 0 }
    ENGLISH_PLURAL = ->(count) { count == 1 ? 0 : 1 }

    # A .po file read into {[msgctxt, msgid] => [form, ...]}, with the header
    # under [nil, ""].
    #
    # Only what msgfmt would keep is kept: an entry that is commented out with
    # "#~", flagged fuzzy, or left with an empty first form is dropped, so the
    # English msgid stands at the call site — which is what the C library does
    # with a catalogue that has a hole in it.
    class PoFile
      # The escapes a .po string can carry. Anything else after a backslash is
      # the character itself.
      ESCAPES = {
        "n"  => "\n",
        "t"  => "\t",
        "r"  => "\r",
        "a"  => "\a",
        "b"  => "\b",
        "f"  => "\f",
        "v"  => "\v",
        "\"" => "\"",
        "\\" => "\\",
      }.freeze

      # msgid_plural has to be offered before msgid, or the shorter keyword
      # would claim the longer one's line.
      KEYWORD = /\A(msgctxt|msgid_plural|msgid|msgstr(?:\[(\d+)\])?)[ \t]+(".*")[ \t]*\z/
      CONTINUATION = /\A".*"\z/
      OBSOLETE = /\A#~/
      FLAGS = /\A#,[ \t]*(.*)\z/
      COMMENT = /\A#/

      def self.read(path)
        new.parse(File.read(path, encoding: Encoding::UTF_8))
      end

      def parse(text)
        @messages = {}
        start_entry
        text.each_line { |line| read_line(line.chomp) }
        flush
        @messages
      end

      private

        def read_line(line)
          case line.strip
          when "" then flush
          when OBSOLETE then @obsolete = true
          when FLAGS then note_flags(Regexp.last_match(1))
          when COMMENT then nil
          when KEYWORD
            open_field(
              Regexp.last_match(1),
              Regexp.last_match(2),
              Regexp.last_match(3),
            )
          when CONTINUATION then extend_field(line.strip)
          end
        end

        def note_flags(flags)
          @fuzzy ||= flags.split(/[\s,]+/).include?("fuzzy")
        end

        # A msgctxt or msgid arriving while forms are already collected starts
        # the next entry — .po files are not required to separate entries with
        # a blank line.
        def open_field(keyword, form_index, quoted)
          if %w[msgctxt msgid].include?(keyword) && !@forms.empty?
            flush
          end

          @field = field_name(keyword, form_index)
          @parts[@field] = unquote(quoted)

          if @field.is_a?(Integer)
            @forms << @field
          end
        end

        def extend_field(quoted)
          if @field
            @parts[@field] += unquote(quoted)
          end
        end

        def field_name(keyword, form_index)
          case keyword
          when "msgctxt" then :msgctxt
          when "msgid" then :msgid
          when "msgid_plural" then :msgid_plural
          else form_index.to_i
          end
        end

        def unquote(quoted)
          quoted[1..-2].gsub(/\\(.)/) do
            Regexp.last_match(1).then { |escaped| ESCAPES.fetch(escaped, escaped) }
          end
        end

        # Files the entry just read under its context and msgid, unless msgfmt
        # would have thrown it away, and clears the slate for the next one.
        def flush
          if keep_entry?
            @messages[[@parts[:msgctxt], @parts[:msgid]]] = translated_forms
          end

          start_entry
        end

        def keep_entry?
          @parts.key?(:msgid) &&
            !@obsolete &&
            !@fuzzy &&
            !translated_forms.first.to_s.empty?
        end

        def translated_forms
          @forms.sort.map { |index| @parts[index] }
        end

        def start_entry
          @parts = {}
          @forms = []
          @field = nil
          @fuzzy = false
          @obsolete = false
        end
    end

    # One locale's messages: the lookup, and the language's plural rule read
    # off the catalogue header.
    class Catalog
      def self.empty = new({})
      def self.load(path) = new(PoFile.read(path))

      def initialize(messages)
        @messages = messages
      end

      # The translation of `msgid` in `context` (nil for the default context),
      # or `msgid` itself when the catalogue has nothing for it.
      def singular(context, msgid)
        @messages[[context, msgid]].then { |forms| forms ? forms.first : msgid }
      end

      # The form of a plural message that `count` selects, falling back to
      # English's own two forms when the catalogue cannot supply them.
      def plural(msgid, msgid_plural, count)
        @messages[[nil, msgid]].then do |forms|
          if forms.nil?
            count == 1 ? msgid : msgid_plural
          else
            forms[plural_index(count)] || forms.last
          end
        end
      end

      private

        # The index into a message's forms for `count`. A rule written in C
        # yields a boolean where Ruby's own operators do, so `n != 1` has to be
        # read back as 0 and 1, and a rule that overruns the header's nplurals
        # is pulled into range.
        def plural_index(count)
          plural_rule.call(count).then do |selected|
            case selected
            when true then 1
            when false then 0
            else selected.to_i
            end
          end.clamp(0, nplurals - 1)
        end

        def plural_rule
          @plural_rule ||= compile_plural_rule
        end

        def compile_plural_rule
          plural_forms[/plural\s*=\s*([^;]+)/, 1].to_s.strip.then do |source|
            if source.match?(SAFE_PLURAL_EXPRESSION)
              # The C expression a catalogue carries is a Ruby expression too:
              # the operators, their precedence and integer division all
              # agree, and `n` — the count, spelled the way every catalogue
              # spells it — is the only name the expression can reach.
              # rubocop:disable Security/Eval
              validate_plural_rule(->(n) { eval(source) })
              # rubocop:enable Security/Eval
            else
              default_plural_rule
            end
          end
        end

        # A rule is only trusted once it has answered for the counts the
        # languages shipped here branch on, without raising.
        def validate_plural_rule(rule)
          [0, 1, 2, 5, 11, 101].each { |count| rule.call(count) }
          rule
        rescue StandardError, SyntaxError
          default_plural_rule
        end

        def default_plural_rule
          nplurals == 1 ? SINGULAR_ONLY : ENGLISH_PLURAL
        end

        def nplurals
          @nplurals ||= plural_forms[/nplurals\s*=\s*(\d+)/, 1].to_i.then do |declared|
            declared.positive? ? declared : 1
          end
        end

        # The catalogue's Plural-Forms header line, e.g.
        # "Plural-Forms: nplurals=2; plural=(n > 1);".
        def plural_forms
          @plural_forms ||= header.lines.map(&:strip).find { |line|
            line.start_with?("Plural-Forms:")
          }.to_s
        end

        def header
          @messages[[nil, ""]].to_a.first.to_s
        end
    end

    # The catalogue for the locale this process is running under, read once.
    def self.catalog
      @catalog ||= catalog_path.then do |path|
        path ? Catalog.load(path) : Catalog.empty
      end
    end

    # The .po file of the first candidate locale a catalogue exists for.
    def self.catalog_path
      locale_candidates
        .lazy
        .map { |tag| File.join(PO_DIR, "#{tag}.po") }
        .find { |path| File.file?(path) }
    end

    # The locales to try, most specific first, read the way the C library reads
    # them: LANGUAGE holds a colon-separated preference list and outranks the
    # single-locale variables, each tag loses its encoding and modifier
    # suffixes, and a tag naming a territory ("pt_BR") also allows its bare
    # language ("pt"). "C" and "POSIX" ask for no translation at all.
    def self.locale_candidates
      ENV.values_at(
        "LANGUAGE",
        "LC_ALL",
        "LC_MESSAGES",
        "LANG",
      )
        .compact
        .flat_map { |value| value.split(":") }
        .map { |tag| tag.sub(/[.@].*\z/, "") }
        .reject { |tag| tag.empty? || %w[C POSIX].include?(tag) }
        .flat_map { |tag| [tag, tag.split("_").first] }
        .uniq
    end

    module_function

    # rubocop:disable Naming/MethodName

    # Upstream's `_()`: the translation of a message, or the message itself
    # under a locale that has no catalogue or no entry for it.
    def _(msgid) = I18n.catalog.singular(nil, msgid)

    # Upstream's `ngettext()`: the form of a message that `count` selects.
    def ngettext(msgid, msgid_plural, count) = I18n.catalog.plural(msgid, msgid_plural, count)

    # Upstream's `C_()`: a message translated inside a disambiguating context,
    # so one English word can be translated differently in different places.
    def C_(context, msgid) = I18n.catalog.singular(context, msgid)

    # rubocop:enable Naming/MethodName

    # Upstream's str.format(): fills in the `{}` and `{named}` placeholders of
    # a message that has already been through `_()` or `ngettext()`. The
    # placeholders stay inside the msgid, where a translator can move them —
    # which is why this exists instead of interpolating in the Ruby source.
    def interpolate(message, *values, **named)
      values.dup.then do |positional|
        message.gsub(/\{(\w*)\}/) do
          placeholder_value(
            Regexp.last_match(1),
            Regexp.last_match(0),
            positional,
            named,
          )
        end
      end
    end

    # The value a single placeholder stands for. Python's str.format raises on
    # a name it was not given; a translation is data, and one that invents a
    # placeholder or asks for more positional values than the call site passes
    # leaves it written out rather than taking the window down with it.
    def placeholder_value(key, placeholder, positional, named)
      if key.empty?
        positional.empty? ? placeholder : positional.shift.to_s
      else
        named.fetch(key.to_sym) { placeholder }.to_s
      end
    end
  end
end
