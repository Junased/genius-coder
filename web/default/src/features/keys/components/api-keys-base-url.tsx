/*
Copyright (C) 2023-2026 QuantumNous

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

For commercial licensing, please contact support@quantumnous.com
*/
import { useTranslation } from 'react-i18next'
import { CopyButton } from '@/components/copy-button'
import { useChatPresets } from '@/features/chat/hooks/use-chat-presets'

const baseUrlClassNames = {
  wrapper:
    'border-border bg-muted/50 text-muted-foreground flex h-8 max-w-[min(72vw,46rem)] items-center gap-1 rounded-lg border px-2 text-sm',
  label: 'text-foreground shrink-0 font-medium',
  item: 'bg-background border-border/70 inline-flex h-6 min-w-0 max-w-full items-center rounded-md border px-2',
  value: 'text-foreground min-w-0 truncate font-mono text-xs',
  copy: 'ml-1 size-6 text-muted-foreground hover:text-foreground',
  copyIcon: 'size-3.5',
  separator: 'shrink-0 px-0.5 text-xs',
}

const appendV1Path = (url: string) => `${url.replace(/\/+$/, '')}/v1`

function BaseUrlCopyItem({
  value,
  tooltip,
}: {
  value: string
  tooltip: string
}) {
  return (
    <span className={baseUrlClassNames.item}>
      <span className={baseUrlClassNames.value} title={value}>
        {value}
      </span>
      <CopyButton
        value={value}
        variant='ghost'
        size='icon'
        className={baseUrlClassNames.copy}
        iconClassName={baseUrlClassNames.copyIcon}
        tooltip={tooltip}
        aria-label={tooltip}
      />
    </span>
  )
}

export function ApiKeysBaseUrl() {
  const { t } = useTranslation()
  const { serverAddress } = useChatPresets()
  const baseUrl = serverAddress.trim()

  if (!baseUrl) return null

  return (
    <div className={baseUrlClassNames.wrapper}>
      <span className={baseUrlClassNames.label}>BaseUrl:</span>
      <BaseUrlCopyItem value={baseUrl} tooltip={`${t('Copy')} BaseUrl`} />
      <span className={baseUrlClassNames.separator}>/</span>
      <BaseUrlCopyItem
        value={appendV1Path(baseUrl)}
        tooltip={`${t('Copy')} BaseUrl /v1`}
      />
    </div>
  )
}
