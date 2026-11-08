"""Geometry importer regression tests; all coordinates below are synthetic."""
import unittest

from build_local_rail_graph import connected_path


class TrackConnectivityTest(unittest.TestCase):
    def setUp(self):
        self.nodes = {i: {'lat': 14.6 + i / 1000, 'lon': 121} for i in range(5)}

    def way(self, ids, railway='light_rail'):
        return {'nodes': ids, 'tags': {'railway': railway}}

    def test_actual_shared_nodes_form_ordered_path(self):
        ways = [self.way([0, 1, 2]), self.way([2, 3, 4])]
        self.assertEqual(connected_path(ways, self.nodes, 0, 4), [0, 1, 2, 3, 4])
        self.assertEqual(connected_path(ways, self.nodes, 4, 0), [4, 3, 2, 1, 0])

    def test_nearby_unconnected_tracks_are_not_joined(self):
        self.assertIsNone(connected_path(
            [self.way([0, 1]), self.way([2, 3])], self.nodes, 0, 3))

    def test_nonrail_way_cannot_bridge_gap(self):
        self.assertIsNone(connected_path(
            [self.way([0, 1]), self.way([1, 2], 'abandoned'), self.way([2, 3])],
            self.nodes, 0, 3))

    def test_missing_nodes_never_become_straight_line(self):
        del self.nodes[1]
        self.assertIsNone(connected_path([self.way([0, 1, 2])], self.nodes, 0, 2))


if __name__ == '__main__':
    unittest.main()
