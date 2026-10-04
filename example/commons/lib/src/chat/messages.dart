/// Default texts of the chat module, editable in `messages/chat.json`.
///
/// Keys starting with `error.` are shown as command errors (red, no color
/// codes). The layouts of chat lines, join messages and private messages are
/// in `chat/config.json` instead.
const chatMessages = <String, String>{
  'muted': '&cYou are muted: &f{reason}&c.{until}',
  'error.muted': 'You are muted: {reason}{until}',
  'spam.fast': '&cSlow down! You can chat again in {wait}.',
  'spam.rate': '&cYou are sending messages too quickly. Wait {wait}.',
  'spam.repeat': "&cPlease don't repeat yourself.",
  'mention.actionBar': '&e{player} &6mentioned you',
  'error.offline': '{name} is not online.',
  'error.self': "You can't message yourself.",
  'error.empty': 'Write a message.',
  'error.noReply': 'You have nobody to reply to.',
  'error.replyGone': '{name} is no longer online.',
  'error.unknownPlayer': 'No player called "{name}" has played here.',
  'error.ignoreSelf': "You can't ignore yourself.",
  'error.exempt': '{name} is staff and cannot be ignored.',
  'ignore.on':
      '&7You now ignore &f{player}&7: their chat and messages are hidden.',
  'ignore.off': '&7You no longer ignore &f{player}&7.',
  'ignore.title': '&eYou ignore:',
  'ignore.none': '&7You are not ignoring anyone.',
  'spy.on': '&aYou now see private messages.',
  'spy.off': '&7You no longer see private messages.',
  'welcome.online': '&7{online} of {max} players online.',
  'welcome.balance': '&7Balance: &e{balance}',
  'welcome.mail': '&7Mail: &e{count} unread ',
  'welcome.daily': '&7Your daily reward is ready! ',
};
