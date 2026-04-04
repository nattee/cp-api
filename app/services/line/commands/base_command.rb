# Base class for slash commands shared by LINE and the web chat playground.
#
# Commands receive a context hash with :line_user_id, :user (optional), and
# :source (either :line or :web). They return a Result that the caller uses
# to deliver the response through the appropriate channel.
#
# LINE path:  MessageRouter builds context from event_data, calls execute,
#             sends result.text via ReplyService.
# Web path:   ChatsController builds context from session, calls execute,
#             shows result.text as a flash message.
class Line::Commands::BaseCommand
  Result = Struct.new(:text, :error, keyword_init: true) do
    def error? = !!error
  end

  attr_reader :context

  def initialize(context)
    @context = context
  end

  def execute(args)
    raise NotImplementedError
  end

  private

  def line_user_id
    context[:line_user_id]
  end

  def current_user
    context[:user]
  end

  def result(text)
    Result.new(text: text)
  end

  def error(text)
    Result.new(text: text, error: true)
  end
end
