#ifndef MINIZ_EXPORT_H
#define MINIZ_EXPORT_H

#if defined(MINIZ_SHARED)
#if defined(_WIN32)
#if defined(MINIZ_IMPLEMENTATION)
#define MINIZ_EXPORT __declspec(dllexport)
#else
#define MINIZ_EXPORT __declspec(dllimport)
#endif
#elif defined(__GNUC__)
#define MINIZ_EXPORT __attribute__((visibility("default")))
#else
#define MINIZ_EXPORT
#endif
#else
#define MINIZ_EXPORT
#endif

#endif /* MINIZ_EXPORT_H */