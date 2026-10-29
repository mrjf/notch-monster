import { Action, ActionPanel, Icon, LaunchProps, List } from "@raycast/api";
import { basename, dirname, isAbsolute } from "node:path";

type FileContext = { paths?: unknown };

export default function CaughtFiles({ launchContext }: LaunchProps<{ launchContext: FileContext }>) {
  const input = launchContext?.paths;
  const paths = Array.isArray(input)
    ? [...new Set(input.filter((value): value is string => typeof value === "string" && isAbsolute(value))) ]
    : [];

  return (
    <List navigationTitle="Caught by Notch Monster" searchBarPlaceholder="Filter caught files…">
      <List.EmptyView
        icon={Icon.Document}
        title="Feed the monster a file"
        description="In Notch Monster Settings, choose Send to Raycast, then drop files near the notch. Your files stay in place until you choose an action."
      />
      {paths.map((path) => (
        <List.Item
          key={path}
          title={basename(path)}
          subtitle={dirname(path)}
          icon={{ fileIcon: path }}
          quickLook={{ path }}
          actions={
            <ActionPanel>
              <Action.OpenWith path={path} />
              <Action.ToggleQuickLook shortcut={{ modifiers: [], key: "space" }} />
              <Action.Open title="Open File" target={path} />
              <Action.ShowInFinder path={path} />
              <Action.CopyToClipboard title="Copy File" content={{ file: path }} />
              <Action.CopyToClipboard title="Copy Path" content={path} />
              {paths.length > 1 && <Action.CopyToClipboard title="Copy All Paths" content={paths.join("\n")} />}
              <Action.Trash paths={path} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
