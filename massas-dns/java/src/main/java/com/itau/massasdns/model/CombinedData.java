package com.itau.massasdns.model;

import java.util.List;

public record CombinedData(List<String> headers, List<List<String>> rows) {}
