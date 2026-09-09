const pages = {
  index: {
    display: 'hidden',
  },
  '---start': {
    type: 'separator',
    title: 'Start here',
  },
  'getting-started': 'Your first app',
  '---guides': {
    type: 'separator',
    title: 'Guides',
  },
  'input-focus': 'Handle input and focus',
  'command-line-arguments': 'Parse command-line arguments',
  testing: 'Test an app',
  '---signals': {
    type: 'separator',
    title: 'noir_signals',
  },
  'noir-signals': 'Overview and setup',
  hooks: 'Manage state and resources',
  signals: 'Show shared state',
  'signals-task-list': 'Build a task list',
  '---concepts': {
    type: 'separator',
    title: 'Concepts',
  },
  'widgets-layout': 'Layout in terminal cells',
  'state-lifecycle': 'State, identity, and ownership',
  '---reference': {
    type: 'separator',
    title: 'Reference',
  },
  'widget-catalog': 'Widget catalog',
  'platform-limitations': 'Platform support',
  installation: {
    display: 'hidden',
  },
  'architecture-api': {
    display: 'hidden',
  },
  widgets: {
    display: 'hidden',
  },
};

export default pages;
