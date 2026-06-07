/*
Copyright (C) 2025 QuantumNous

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

import React, { useState } from 'react';
import { Button } from '@douyinfe/semi-ui';
import { IconCopy } from '@douyinfe/semi-icons';
import {
  copy,
  getServerAddress,
  showError,
  showSuccess,
} from '../../../helpers';
import CopyTokensModal from './modals/CopyTokensModal';
import DeleteTokensModal from './modals/DeleteTokensModal';

const appendV1Path = (url) => `${url.replace(/\/+$/, '')}/v1`;

const BaseUrlCopyItem = ({ value, copyLabel, onCopy }) => (
  <span className='token-base-url-item'>
    <span className='token-base-url-value' title={value}>
      {value}
    </span>
    <Button
      theme='borderless'
      type='tertiary'
      size='small'
      className='token-base-url-copy'
      icon={<IconCopy />}
      aria-label={copyLabel}
      onClick={() => onCopy(value)}
    />
  </span>
);

const TokensActions = ({
  selectedKeys,
  setEditingToken,
  setShowEdit,
  batchCopyTokens,
  batchDeleteTokens,
  t,
}) => {
  // Modal states
  const [showCopyModal, setShowCopyModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);

  // Handle copy selected tokens with options
  const handleCopySelectedTokens = () => {
    if (selectedKeys.length === 0) {
      showError(t('请至少选择一个令牌！'));
      return;
    }
    setShowCopyModal(true);
  };

  // Handle delete selected tokens with confirmation
  const handleDeleteSelectedTokens = () => {
    if (selectedKeys.length === 0) {
      showError(t('请至少选择一个令牌！'));
      return;
    }
    setShowDeleteModal(true);
  };

  const baseUrl = getServerAddress();
  const baseUrlWithV1 = appendV1Path(baseUrl);

  const handleCopyBaseUrl = async (url) => {
    if (await copy(url)) {
      showSuccess(t('已复制到剪贴板！'));
    } else {
      showError(t('复制失败，请手动复制'));
    }
  };

  // Handle delete confirmation
  const handleConfirmDelete = () => {
    batchDeleteTokens();
    setShowDeleteModal(false);
  };

  return (
    <>
      <div className='flex flex-wrap gap-2 w-full md:w-auto order-2 md:order-1'>
        <Button
          type='primary'
          className='flex-1 md:flex-initial'
          onClick={() => {
            setEditingToken({
              id: undefined,
            });
            setShowEdit(true);
          }}
          size='small'
        >
          {t('添加令牌')}
        </Button>

        <Button
          type='tertiary'
          className='flex-1 md:flex-initial'
          onClick={handleCopySelectedTokens}
          size='small'
        >
          {t('复制所选令牌')}
        </Button>

        <Button
          type='danger'
          className='w-full md:w-auto'
          onClick={handleDeleteSelectedTokens}
          size='small'
        >
          {t('删除所选令牌')}
        </Button>

        <div className='token-base-url'>
          <span className='token-base-url-label'>BaseUrl:</span>
          <BaseUrlCopyItem
            value={baseUrl}
            copyLabel={`${t('复制')} BaseUrl`}
            onCopy={handleCopyBaseUrl}
          />
          <span className='token-base-url-separator'>/</span>
          <BaseUrlCopyItem
            value={baseUrlWithV1}
            copyLabel={`${t('复制')} BaseUrl /v1`}
            onCopy={handleCopyBaseUrl}
          />
        </div>
      </div>

      <CopyTokensModal
        visible={showCopyModal}
        onCancel={() => setShowCopyModal(false)}
        batchCopyTokens={batchCopyTokens}
        t={t}
      />

      <DeleteTokensModal
        visible={showDeleteModal}
        onCancel={() => setShowDeleteModal(false)}
        onConfirm={handleConfirmDelete}
        selectedKeys={selectedKeys}
        t={t}
      />
    </>
  );
};

export default TokensActions;
