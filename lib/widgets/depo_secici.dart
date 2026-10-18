import 'package:flutter/material.dart';

import '../database/models.dart';

IconData depoIkonu(Depo d) =>
    d.arac ? Icons.local_shipping_outlined : Icons.warehouse_outlined;

/// Depo ve araç (seyyar depo) seçim listeleri için ortak öğeler: araçlar
/// kamyon simgesiyle, depolar depo simgesiyle görünür.
List<DropdownMenuItem<String>> depoDropdownOgeleri(List<Depo> depolar) => [
      for (final d in depolar)
        DropdownMenuItem(
          value: d.id,
          child: Row(
            children: [
              Icon(depoIkonu(d), size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text(d.ad, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ];
