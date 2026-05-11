/**
 * @format
 */

import React from 'react';
import renderer from 'react-test-renderer';
import {Text} from 'react-native';
import {iconGlyph, pageGroups} from '../src/model';

test('groups pages by sidebar group', () => {
  const groups = pageGroups({
    pages: [
      {id: 'fastq', title: 'FastQ'},
      {id: 'library', title: 'Library', sidebarGroup: 'tools'},
      {id: 'settings', title: 'Settings', sidebarGroup: 'tools'},
    ],
  });
  expect(groups).toHaveLength(2);
  expect(groups[1].pages).toHaveLength(2);
});

test('renders icon glyph text', () => {
  const tree = renderer.create(<Text>{iconGlyph('terminal')}</Text>).toJSON();
  expect(tree).toMatchSnapshot();
});
