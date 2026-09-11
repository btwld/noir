// The layout lifts these entries to the top of the sidebar, so a reader sees
// the groups directly instead of one Docs folder around them.
const pages = {
  index: {
    display: 'hidden',
  },
  '---start': {
    type: 'separator',
    title: 'Start here',
  },
  installation: 'Installation',
  'getting-started': 'Your first app',
  '---guides': {
    type: 'separator',
    title: 'Guides',
  },
  'input-focus': 'Handle input and focus',
  'command-line-arguments': 'Parse command-line arguments',
  testing: 'Test an app',
  '---concepts': {
    type: 'separator',
    title: 'Concepts',
  },
  'widgets-layout': 'Layout in terminal cells',
  'state-lifecycle': 'State, identity, and ownership',
  'architecture-api': 'Architecture',
  '---signals': {
    type: 'separator',
    title: 'noir_signals',
  },
  'noir-signals': 'Overview and setup',
  hooks: 'Manage state and resources',
  signals: 'Show shared state',
  'signals-task-list': 'Build a task list',
  '---reference': {
    type: 'separator',
    title: 'Reference',
  },
  'widget-catalog': 'Widget catalog',
  'platform-limitations': 'Platform support',
  widgets: {
    display: 'hidden',
  },
};

export default pages;
