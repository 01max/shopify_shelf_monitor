# frozen_string_literal: true

# File-based notifier for local debugging.
#
# Duck-types to +Telegram::ChatService+ (+deliver+, +send_media_group+).
# Appends timestamped output to +tmp/debug_output.txt+.
class DebugNotifier
  OUTPUT_PATH = File.join('tmp', 'debug_output.txt')

  # @param _opts [Hash] ignored; accepted for duck-type compatibility with +Telegram::ChatService+
  def initialize(**_opts)
    FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
  end

  # @param text [String]
  # @return [void]
  def deliver(text, **_opts)
    append("[MESSAGE] #{text}")
  end

  # @param photo_urls [Array<String>]
  # @return [void]
  def send_media_group(photo_urls)
    photo_urls.each { |url| append("[PHOTO] #{url}") }
  end

  private

  # @param content [String] message line to timestamp and persist
  # @return [void]
  def append(content)
    full_content = "[#{Time.now}] #{content}"
    puts full_content
    File.open(OUTPUT_PATH, 'a') { |f| f.puts(full_content) }
  end
end
