# include config
. ".\config.ps1"


$headers = @{}
$headers.Add("Authorization", "Bearer $NOTION_KEY")
$headers.Add("Content-Type", "application/json")
$headers.Add("Notion-Version", $NOTION_VERSION)

$body = @{
    filter = @{
        property = "Status"
        rich_text = @{
            does_not_equal = "終了"
        }
    }
} | ConvertTo-Json -Depth 3

$pageids = @{}
$response = Invoke-RestMethod "https://api.notion.com/v1/databases/$DATABASE_ID/query" -Method 'POST' -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
if ($null -ne $response.results) {
    foreach ($res in $response.results) {
        if ($null -ne $res.properties.ticket_id.rich_text.plain_text) {
            $page = @{}
            $page.Add("pageid", $res.id)
            $page.Add("status", $res.properties.Status.rich_text.plain_text)
            $page.Add("ticket_title", $res.properties.ticket_title.title.plain_text)
            $page.Add("due_date", $res.properties."d-date".date.start)
            $pageids.Add($res.properties.ticket_id.rich_text.plain_text, $page)
        }
    }
}

$headers2 = @{}
$headers2.Add("Content-Type", "application/json")
$headers2.Add("X-Redmine-API-Key", $REDMINE_API_KEY)
$response = Invoke-RestMethod "$REDMINE_DOMAIN/issues.json?query_id=216" -Method 'GET' -Headers $headers2

#$database_id = "e3d1f8b6af584c9586314e9ac7de0a6d"
If ($null -ne $response.issues) {
    
    foreach ($item in $response.issues) {
        $ticket_id = $item.id
        $status = $item.status.name
        $ticket_title = $item.subject.Replace('"', '\"')
        $due_date = $item.due_date
        #$printmsg = $ticket_id,$ticket_title,$status -join "    "
        $printmsg = "[$ticket_id] $ticket_title ($status)"
        if ($pageids.ContainsKey("$ticket_id") -eq $false) {
            $body = @{
                parent = @{
                    database_id = $DATABASE_ID
                }
                properties = @{
                    ticket_id = @{
                        rich_text = @(
                            @{
                                type = "text"
                                text = @{
                                    content = [string]$ticket_id
                                    link = @{
                                        url = "$REDMINE_DOMAIN/issues/$ticket_id"
                                    }
                                }
                            }
                        )
                    }
                    ticket_title = @{
                        title = @(
                            @{
                                type = "text"
                                text = @{
                                    content = $ticket_title
                                }
                            }
                        )
                    }
                    Status = @{
                        rich_text = @(
                            @{
                                type = "text"
                                text = @{
                                    content = $status
                                }
                            }
                        )
                    }
                    "d-date" = @{
                        date = @{
                            start = $due_date
                            end = $null
                        }
                    }
                }
            }
            $body = $body | ConvertTo-Json -Depth 6
            Write-Output "--Insert--"
            Write-Output $printmsg
            $res2 = Invoke-RestMethod 'https://api.notion.com/v1/pages/' -Method 'POST' -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
        } else {
            $is_diff = $false;
            $body = @{ properties = @{}}
            $printmsg = "[$ticket_id]`n"
            if ($status -ne $pageids["$ticket_id"].status) {
                $body.properties.Add("Status", @{
                    rich_text = @(
                        @{
                            type = "text"
                            text = @{
                                content = $status
                            }
                        }
                    )
                })
                $is_diff = $true
                $printmsg += "`t($($pageids["$ticket_id"].status)) => ($status)`n"
            }
            if ($ticket_title -ne $pageids["$ticket_id"].ticket_title) {
                $body.properties.Add("ticket_title", @{
                    title = @(
                        @{
                            type = "text"
                            text = @{
                                content = $ticket_title
                            }
                        }
                    )
                })
                $is_diff = $true
                $printmsg += "`t($($pageids["$ticket_id"].ticket_title)) => ($ticket_title)`n"
            }
            if ($due_date -ne $pageids["$ticket_id"].due_date) {
                $body.properties.Add("d-date", @{
                    date = @{
                        start = $due_date
                        end = $null
                    }
                })
                $is_diff = $true
                $printmsg += "`t($($pageids["$ticket_id"].due_date)) => ($due_date)`n"
            }
            if ($true -eq $is_diff) {
                # ConvertTo-Json -Depth 4
                $body = $body | ConvertTo-Json -Depth 5
                Write-Output "--Update--"
                Write-Output $printmsg
                $url = "https://api.notion.com/v1/pages/" + $pageids["$ticket_id"].pageid
                $res2 = Invoke-RestMethod $url -Method 'PATCH' -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
            }

            $pageids.Remove("$ticket_id")
        }
    }

}

foreach ($key in $pageids.Keys) {
    $url = "$REDMINE_DOMAIN/issues/$key.json"
    $issue = Invoke-RestMethod $url -Method 'GET' -Headers $headers2
    if ($null -ne $issue.issue.status.name) {
        Write-Output "--Finish--"
        $printmsg = $key,$issue.issue.subject,$issue.issue.status.name -join "    "
        Write-Output $printmsg
        $status = $issue.issue.status.name
        $body = @{
            properties = @{
                Status = @{
                    rich_text = @(
                        @{
                            type = "text"
                            text = @{
                                content = $status
                            }
                        }
                    )
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 5
        $url = "https://api.notion.com/v1/pages/" + $pageids.$key.pageid
        $res2 = Invoke-RestMethod $url -Method 'PATCH' -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    }
}

Write-Output "Done."

pause


